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
--8<-- "recipes/go_llm_lib/streaming_response/go/go.mod:deps"
```

## Importing the Library

The program imports the `llm` package for the client and the request
types, and the blank import of `llm/all` registers every provider. The
program also imports `errors` and `io`, because a stream signals its end
with `io.EOF`. The following snippet shows the imports:

```go
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:imports"
```

## Configuring the Provider

The program reads the provider, model, API key, and base URL from the
environment. When `LLM_BASE_URL` is unset or empty, the program passes no
base URL, and the library uses the default endpoint of the chosen
provider. The following snippet shows how the program reads the variables:

```go
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:config"
```

## Creating the Client

The program creates the client with `llm.NewClient()`, which returns the
same `llm.Client` interface for every provider. The options cap the reply
at 64 tokens and limit the retry policy to two retries, so that the
example runs quickly. The following snippet shows how the program creates
the client:

```go
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:client"
```

## Opening the Stream

The program calls `ChatStream()` instead of `Chat()`, with the same
`llm.ChatRequest`. The call returns as soon as the provider starts to
respond, with a `*llm.Stream` that delivers the reply in pieces. A failure
to reach the provider appears here, as the error from `ChatStream()`. The
following snippet shows how the program opens the stream:

```go
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:stream"
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
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:read"
```

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
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go:main"
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
--8<-- "recipes/go_llm_lib/streaming_response/go/main.go"
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
