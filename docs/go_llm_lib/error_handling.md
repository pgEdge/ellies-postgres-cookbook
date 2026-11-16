# Handling Provider Errors and Retries

This recipe shows how a Go program tells the failures of a language model
provider apart, and how it controls the retries that the
[pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
makes on its behalf. A request can fail because the provider rejects it,
or because the program never reaches the provider, and an application
usually reacts differently to each. The example builds on the
[Sending a Chat Request](chat_request.md) recipe, which explains the
environment variables and how to run the examples against a local
[Ollama](https://ollama.com) server.

The example causes two failures on purpose: it asks Ollama for a model
that does not exist, and then it sends a request to a port with nothing
listening on it, with two quick retries. Both failures are the same on
every run, so the output is fixed:

```text
Missing model: provider error
Missing model status: 404
Retry 1: status 0, network error: true
Retry 2: status 0, network error: true
Unreachable server: network error
Retries: 2
```

## Preparing the Ingredients

The example needs Go and the library, which the `go.mod` file pins at
version 0.6.0, and it uses a local Ollama server for the first failure.
The following snippet shows the dependency declaration from the example
project:

```text
// The pgEdge Go LLM Library has no dependencies of its own.
require github.com/pgEdge/pgedge-go-llm-lib v0.6.0

```

## Importing the Library

The program imports the `llm` package, which defines the error types, and
the blank import of `llm/all` registers every provider. The `errors`
package matches the errors, and `net` identifies a network failure. The
following snippet shows the imports:

```go
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

```

## Configuring the Provider

The program reads the provider, model, API key, and base URL from the same
environment variables as the other recipes, and treats an empty variable as
unset. The following snippet shows how the program reads the variables:

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

This version of `newClient()` takes a retry policy and a retry hook, so
that each demonstration can choose how patient its client is. The library
retries a transient failure, which means a network error, an HTTP 429
status, or a 500, 502, 503, or 504 status, and it waits for twice as long
before each further attempt. The `llm.RetryConfig` type sets the limits:

| Field            | Default | Description                              |
|------------------|---------|------------------------------------------|
| `MaxRetries`     | 5       | The number of retries after the first attempt. |
| `InitialBackoff` | 2s      | The wait before the first retry.         |
| `MaxBackoff`     | 60s     | The longest wait between two attempts.   |
| `Disabled`       | false   | Sends each request once, with no retries. |

The `OnRetry` option holds a function that the library calls before it
sleeps and retries, which is the place to log the retries or to count
them. The following snippet shows how the program creates the client:

```go
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

```

## Classifying an Error

The library returns every failure that came from a provider as a
`*llm.ProviderError`, which wraps one of five sentinel errors that say what
kind of failure it was: `llm.ErrAuthentication`, `llm.ErrRateLimit`,
`llm.ErrInvalidRequest`, `llm.ErrNotSupported`, and `llm.ErrProviderError`
for everything else. Test for a sentinel error with `errors.Is()`, which
works the same way for every provider. Use `errors.As()` to extract the
`*llm.ProviderError` when the details matter: its `StatusCode` field holds
the HTTP status, and its `Message` and `Provider` fields hold the text and
the name of the provider.

A request that never reaches the provider returns a network error instead,
which is not a `*llm.ProviderError`. The program recognises it by matching
`net.Error` with `errors.As()`. The following snippet shows both checks:

```go
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
	// provider response, so it is a network error instead. A request
	// that exceeds its deadline (context.DeadlineExceeded) also
	// satisfies net.Error, but a cancelled context (context.Canceled)
	// does not, and falls through to the unknown case.
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

```

## Failing on a Missing Model

The first demonstration asks Ollama for a model named `no-such-model`, with
retries turned off. This step always uses the `ollama` provider whatever
`LLM_PROVIDER` says, because the output shown at the top of this page describes
the errors that Ollama returns. When `LLM_PROVIDER` names another provider, the
step also ignores `LLM_BASE_URL` and `LLM_API_KEY`, and the request goes to the
default local Ollama server. The server answers with a 404 status, which is not
transient, so the library would not retry it anyway. Ollama reports every
failure as `llm.ErrProviderError`, whereas a hosted provider such as OpenAI
would map a bad API key to `llm.ErrAuthentication` and a malformed request to
`llm.ErrInvalidRequest`. The function returns an error if the failure is not a
response from the provider, because that means that the server is unreachable.
The following snippet shows the demonstration:

```go
// missingModel asks for a model that does not exist. The server answers
// with an HTTP error, which the library returns as a *llm.ProviderError.
func missingModel(ctx context.Context, cfg config) error {
	// The expected output assumes Ollama. When the environment names
	// another provider, its endpoint and key do not apply to Ollama, so
	// they are cleared and the request goes to the default local server.
	if cfg.provider != "ollama" {
		cfg.provider = "ollama"
		cfg.baseURL = ""
		cfg.apiKey = ""
	}
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

```

## Retrying an Unreachable Server

The second demonstration sends a request to a closed port on the local
host. The library retries the network error twice, starting with a wait of
50 milliseconds that doubles up to a limit of 100 milliseconds; the hook
prints each attempt and counts it. The `StatusCode` of each retry event is
zero because no response arrived, and the `Err` field holds the network
error. When the retries run out, the library returns the last network
error. The following snippet shows the demonstration:

```go
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

```

!!! tip

    The default policy waits for 2, 4, 8, 16, and then 32 seconds before
    giving up, which is far too long for an interactive program. Choose
    values that match how long a person will wait.

## Handling Errors

The main part of the program runs both demonstrations in turn. It returns
any error to `main()`, which reports the error on `stderr` and exits with a
non-zero status; the example therefore fails if the Ollama server is
unreachable, because the first demonstration needs a response from it. The
following snippet shows the main part of the program:

```go
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

```

## Running the Example

The complete project is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/error_handling).
With Ollama running, run the following command from the `go` project
directory:

```bash
go run .
```

## Viewing the Complete Program

The following snippet shows the complete program:

```go
// Ellie's Postgres Cookbook
// Handling provider errors and retries with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

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
	// provider response, so it is a network error instead. A request
	// that exceeds its deadline (context.DeadlineExceeded) also
	// satisfies net.Error, but a cancelled context (context.Canceled)
	// does not, and falls through to the unknown case.
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


// missingModel asks for a model that does not exist. The server answers
// with an HTTP error, which the library returns as a *llm.ProviderError.
func missingModel(ctx context.Context, cfg config) error {
	// The expected output assumes Ollama. When the environment names
	// another provider, its endpoint and key do not apply to Ollama, so
	// they are cleared and the request goes to the default local server.
	if cfg.provider != "ollama" {
		cfg.provider = "ollama"
		cfg.baseURL = ""
		cfg.apiKey = ""
	}
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


```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Sending a Chat Request](chat_request.md) recipe explains the
  environment variables and how to switch providers.
- The [Streaming a Response](streaming_response.md) recipe shows how to detect
  a stream that fails or ends early.
- The
  [pgEdge Go LLM Library documentation](https://github.com/pgEdge/pgedge-go-llm-lib/tree/main/docs)
  describes the retry policy and the error types in detail.
