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
--8<-- "recipes/go_llm_lib/error_handling/go/go.mod:deps"
```

## Importing the Library

The program imports the `llm` package, which defines the error types, and
the blank import of `llm/all` registers every provider. The `errors`
package matches the errors, and `net` identifies a network failure. The
following snippet shows the imports:

```go
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:imports"
```

## Configuring the Provider

The program reads the provider, model, API key, and base URL from the same
environment variables as the other recipes, and treats an empty variable as
unset. The following snippet shows how the program reads the variables:

```go
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:config"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:client"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:classify"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:missing"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:retry"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go:main"
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
--8<-- "recipes/go_llm_lib/error_handling/go/main.go"
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
