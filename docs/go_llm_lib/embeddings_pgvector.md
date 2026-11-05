# Storing Embeddings in PostgreSQL

This recipe shows how a Go program turns text into embedding vectors with
the pgEdge Go LLM Library, stores the vectors in a PostgreSQL table with the
pgvector extension, and finds the stored text that is closest in meaning to
a question. The example is written in Go only, because the library is a Go
package.

The example program embeds five short documents, one of which is about a
cat, and then embeds the question "Which animal purrs?". It prints the
document that lies nearest to the question. The cat document should win,
whichever reasonable embedding model the program uses:

```text
Question: Which animal purrs?
Nearest document: The cat curled up on the sofa and purred contentedly.
```

## Preparing the Ingredients

The example needs a PostgreSQL server on which the pgvector extension is
available, and an embedding provider. By default, the example uses a local
[Ollama](https://ollama.com/) server with the `nomic-embed-text` model; the
following commands pull the model:

```bash
ollama pull nomic-embed-text
```

The example uses the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
to create the embeddings and [pgx](https://github.com/jackc/pgx) to talk to
PostgreSQL. The following code shows the dependency declaration from the
example project:

```go
// The pgEdge Go LLM Library provides one client for many providers.
require github.com/pgEdge/pgedge-go-llm-lib v0.6.0

// pgx is a pure Go driver and toolkit for PostgreSQL.
require github.com/jackc/pgx/v5 v5.12.0

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.41.0 // indirect
)

```

## Importing the Libraries

The program imports pgx and the library. The blank import of the `llm/all`
package registers every provider that the library supports, so the program
can pick a provider by name at run time. The following code shows the
imports:

```go
import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)

```

## Configuring the Program

The program reads its settings from environment variables, and treats an
empty variable as unset. The five `PG*` variables describe the database
connection exactly as in the
[first recipe](../postgresql/connect_and_query.md). The following table
describes the other variables that the program reads:

| Variable         | Default            | Description                        |
|------------------|--------------------|------------------------------------|
| `LLM_PROVIDER`   | `ollama`           | Decides whether the next two       |
|                  |                    | variables apply to embeddings.     |
| `LLM_API_KEY`    | None               | The API key; used only when the    |
|                  |                    | two providers match.               |
| `LLM_BASE_URL`   | The provider's own | The endpoint; used only when the   |
|                  |                    | two providers match.               |
| `EMBED_PROVIDER` | `ollama`           | The provider for embeddings.       |
| `EMBED_MODEL`    | `nomic-embed-text` | The embedding model.               |

This recipe creates only embeddings, so it ignores `LLM_MODEL`. The
following code shows how the program reads the variables:

```go
// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// config holds the settings that the program reads from the environment.
type config struct {
	llmProvider   string
	embedProvider string
	embedModel    string
	apiKey        string
	baseURL       string
	connString    string
}

// loadConfig reads the LLM_*, EMBED_*, and PG* environment variables. An
// empty variable counts as unset.
func loadConfig() config {
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

	return config{
		llmProvider:   envOr("LLM_PROVIDER", "ollama"),
		embedProvider: envOr("EMBED_PROVIDER", "ollama"),
		embedModel:    envOr("EMBED_MODEL", "nomic-embed-text"),
		apiKey:        os.Getenv("LLM_API_KEY"),
		baseURL:       os.Getenv("LLM_BASE_URL"),
		connString:    u.String(),
	}
}

```

## Creating the Client

The library represents every provider as an `llm.Client`. The program builds
one with `llm.NewClient`, passing the provider name and the model in an
`llm.Options` value. The API key and the base URL apply only when the
embedding provider is also the chat provider, because one key rarely works
for two providers; otherwise the library falls back to the provider's own
default endpoint and reads the key from the provider's own environment
variable, such as `VOYAGE_API_KEY`. The retry settings keep the wait short
when the provider is unreachable. The following code builds the client:

```go
// newEmbedClient builds the client that creates embeddings. The API key and
// base URL apply only when the embedding provider is the same as the chat
// provider; otherwise the library uses the provider's own defaults and
// reads its key from the provider's own environment variable.
func newEmbedClient(cfg config) (llm.Client, error) {
	opts := llm.Options{
		Model: cfg.embedModel,
		// Retry briefly, so that an unreachable server fails quickly.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
			MaxBackoff:     time.Second,
		},
	}
	if cfg.embedProvider == cfg.llmProvider {
		opts.APIKey = cfg.apiKey
		opts.BaseURL = cfg.baseURL
	}

	client, err := llm.NewClient(cfg.embedProvider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the embedding client failed: %w", err)
	}
	return client, nil
}

```

## Creating the Embeddings

The `EmbedBatch` method sends several texts in one call and returns one
vector per text, in the same order. Each vector is a slice of `float64`
values. The program also converts a vector to the text form that pgvector
reads, such as `[0.1,0.2,0.3]`; passing the text with a `::vector` cast
means that the program needs no extra driver for the `vector` type. The
following code shows both steps:

```go
// embedTexts asks the provider for one embedding vector per text, returned
// in the same order as the texts.
func embedTexts(ctx context.Context, client llm.Client, texts []string) ([][]float64, error) {
	vectors, err := client.EmbedBatch(ctx, texts)
	if err != nil {
		return nil, fmt.Errorf("embedding failed: %w", err)
	}
	if len(vectors) != len(texts) || len(vectors[0]) == 0 {
		return nil, fmt.Errorf("the provider returned an unexpected number of vectors")
	}
	return vectors, nil
}

// vectorLiteral formats an embedding as the text form of a pgvector value,
// such as [0.1,0.2,0.3].
func vectorLiteral(vector []float64) string {
	parts := make([]string, len(vector))
	for i, x := range vector {
		parts[i] = strconv.FormatFloat(x, 'g', -1, 32)
	}
	return "[" + strings.Join(parts, ",") + "]"
}

```

## Storing the Embeddings

A pgvector column has a fixed number of dimensions, and that number depends
on the model. The program therefore takes the size from the length of the
first vector that the provider returns, rather than hard-coding it. The
table is `TEMPORARY`, so it disappears when the connection closes and the
example can run repeatedly. The following code creates the table and
inserts the documents:

```go
// storeDocuments creates a temporary table whose vector column has the
// same number of dimensions as the embeddings, and inserts the documents.
func storeDocuments(ctx context.Context, conn *pgx.Conn, texts []string, vectors [][]float64) error {
	if _, err := conn.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
		return fmt.Errorf("creating the extension failed: %w", err)
	}

	// The dimension count is an integer taken from the embedding, so it is
	// safe to format into the statement; SQL cannot take it as a parameter.
	dims := len(vectors[0])
	create := fmt.Sprintf(
		"CREATE TEMPORARY TABLE documents (id int PRIMARY KEY, body text, embedding vector(%d))",
		dims)
	if _, err := conn.Exec(ctx, create); err != nil {
		return fmt.Errorf("creating the table failed: %w", err)
	}

	for i, text := range texts {
		_, err := conn.Exec(ctx,
			"INSERT INTO documents (id, body, embedding) VALUES ($1, $2, $3::vector)",
			i+1, text, vectorLiteral(vectors[i]))
		if err != nil {
			return fmt.Errorf("insert failed: %w", err)
		}
	}
	return nil
}

```

## Searching by Similarity

The `<=>` operator returns the cosine distance between two vectors, and
ordering by that distance puts the closest document first. The following
code runs the search and returns the nearest document:

```go
// nearest returns the document whose embedding is closest to the question,
// using the cosine distance operator (<=>).
func nearest(ctx context.Context, conn *pgx.Conn, question []float64) (string, error) {
	var body string
	err := conn.QueryRow(ctx,
		"SELECT body FROM documents ORDER BY embedding <=> $1::vector LIMIT 1",
		vectorLiteral(question),
	).Scan(&body)
	if err != nil {
		return "", fmt.Errorf("search failed: %w", err)
	}
	return body, nil
}

```

## Handling Errors and Closing the Connection

The `run` function embeds the documents and the question in a single batch
before it opens a database connection, so a provider failure leaves nothing
behind. The deferred call closes the connection, which also drops the
temporary table. The `main` function reports any error on `stderr` and
exits with a non-zero status. The following code shows both functions:

```go
// run embeds the documents and the question, stores the documents, and
// prints the document nearest to the question.
func run(ctx context.Context) error {
	cfg := loadConfig()

	client, err := newEmbedClient(cfg)
	if err != nil {
		return err
	}

	texts := []string{
		"The cat curled up on the sofa and purred contentedly.",
		"The stock market closed higher after strong earnings reports.",
		"Bake the bread at 220 degrees for thirty minutes.",
		"The new library opens at nine and closes at five.",
		"A rocket lifted off from the launch pad at dawn.",
	}
	question := "Which animal purrs?"

	inputs := make([]string, 0, len(texts)+1)
	inputs = append(inputs, texts...)
	inputs = append(inputs, question)

	// Embed the documents and the question in one batch, before touching
	// the database, so a provider failure never leaves a half-filled table.
	vectors, err := embedTexts(ctx, client, inputs)
	if err != nil {
		return err
	}

	conn, err := pgx.Connect(ctx, cfg.connString)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	// The deferred call closes the connection, which also drops the
	// temporary table.
	defer conn.Close(ctx)

	if err := storeDocuments(ctx, conn, texts, vectors[:len(texts)]); err != nil {
		return err
	}

	body, err := nearest(ctx, conn, vectors[len(texts)])
	if err != nil {
		return err
	}

	fmt.Printf("Question: %s\n", question)
	fmt.Printf("Nearest document: %s\n", body)
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

The following commands run the example against a local PostgreSQL server
and a local Ollama server:

```bash
export PGHOST=localhost PGUSER=postgres
cd recipes/go_llm_lib/embeddings_pgvector/go
go run .
```

To use a different provider, set the `EMBED_*` variables; for example,
`EMBED_PROVIDER=openai EMBED_MODEL=text-embedding-3-small` with
`LLM_PROVIDER=openai` and `LLM_API_KEY` set.

## Viewing the Complete Program

The following code shows the complete program:

```go
// Ellie's Postgres Cookbook
// Storing embeddings in PostgreSQL with pgvector and searching them, using
// the pgEdge Go LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
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

// config holds the settings that the program reads from the environment.
type config struct {
	llmProvider   string
	embedProvider string
	embedModel    string
	apiKey        string
	baseURL       string
	connString    string
}

// loadConfig reads the LLM_*, EMBED_*, and PG* environment variables. An
// empty variable counts as unset.
func loadConfig() config {
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

	return config{
		llmProvider:   envOr("LLM_PROVIDER", "ollama"),
		embedProvider: envOr("EMBED_PROVIDER", "ollama"),
		embedModel:    envOr("EMBED_MODEL", "nomic-embed-text"),
		apiKey:        os.Getenv("LLM_API_KEY"),
		baseURL:       os.Getenv("LLM_BASE_URL"),
		connString:    u.String(),
	}
}


// newEmbedClient builds the client that creates embeddings. The API key and
// base URL apply only when the embedding provider is the same as the chat
// provider; otherwise the library uses the provider's own defaults and
// reads its key from the provider's own environment variable.
func newEmbedClient(cfg config) (llm.Client, error) {
	opts := llm.Options{
		Model: cfg.embedModel,
		// Retry briefly, so that an unreachable server fails quickly.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
			MaxBackoff:     time.Second,
		},
	}
	if cfg.embedProvider == cfg.llmProvider {
		opts.APIKey = cfg.apiKey
		opts.BaseURL = cfg.baseURL
	}

	client, err := llm.NewClient(cfg.embedProvider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the embedding client failed: %w", err)
	}
	return client, nil
}


// embedTexts asks the provider for one embedding vector per text, returned
// in the same order as the texts.
func embedTexts(ctx context.Context, client llm.Client, texts []string) ([][]float64, error) {
	vectors, err := client.EmbedBatch(ctx, texts)
	if err != nil {
		return nil, fmt.Errorf("embedding failed: %w", err)
	}
	if len(vectors) != len(texts) || len(vectors[0]) == 0 {
		return nil, fmt.Errorf("the provider returned an unexpected number of vectors")
	}
	return vectors, nil
}

// vectorLiteral formats an embedding as the text form of a pgvector value,
// such as [0.1,0.2,0.3].
func vectorLiteral(vector []float64) string {
	parts := make([]string, len(vector))
	for i, x := range vector {
		parts[i] = strconv.FormatFloat(x, 'g', -1, 32)
	}
	return "[" + strings.Join(parts, ",") + "]"
}


// storeDocuments creates a temporary table whose vector column has the
// same number of dimensions as the embeddings, and inserts the documents.
func storeDocuments(ctx context.Context, conn *pgx.Conn, texts []string, vectors [][]float64) error {
	if _, err := conn.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
		return fmt.Errorf("creating the extension failed: %w", err)
	}

	// The dimension count is an integer taken from the embedding, so it is
	// safe to format into the statement; SQL cannot take it as a parameter.
	dims := len(vectors[0])
	create := fmt.Sprintf(
		"CREATE TEMPORARY TABLE documents (id int PRIMARY KEY, body text, embedding vector(%d))",
		dims)
	if _, err := conn.Exec(ctx, create); err != nil {
		return fmt.Errorf("creating the table failed: %w", err)
	}

	for i, text := range texts {
		_, err := conn.Exec(ctx,
			"INSERT INTO documents (id, body, embedding) VALUES ($1, $2, $3::vector)",
			i+1, text, vectorLiteral(vectors[i]))
		if err != nil {
			return fmt.Errorf("insert failed: %w", err)
		}
	}
	return nil
}


// nearest returns the document whose embedding is closest to the question,
// using the cosine distance operator (<=>).
func nearest(ctx context.Context, conn *pgx.Conn, question []float64) (string, error) {
	var body string
	err := conn.QueryRow(ctx,
		"SELECT body FROM documents ORDER BY embedding <=> $1::vector LIMIT 1",
		vectorLiteral(question),
	).Scan(&body)
	if err != nil {
		return "", fmt.Errorf("search failed: %w", err)
	}
	return body, nil
}


// run embeds the documents and the question, stores the documents, and
// prints the document nearest to the question.
func run(ctx context.Context) error {
	cfg := loadConfig()

	client, err := newEmbedClient(cfg)
	if err != nil {
		return err
	}

	texts := []string{
		"The cat curled up on the sofa and purred contentedly.",
		"The stock market closed higher after strong earnings reports.",
		"Bake the bread at 220 degrees for thirty minutes.",
		"The new library opens at nine and closes at five.",
		"A rocket lifted off from the launch pad at dawn.",
	}
	question := "Which animal purrs?"

	inputs := make([]string, 0, len(texts)+1)
	inputs = append(inputs, texts...)
	inputs = append(inputs, question)

	// Embed the documents and the question in one batch, before touching
	// the database, so a provider failure never leaves a half-filled table.
	vectors, err := embedTexts(ctx, client, inputs)
	if err != nil {
		return err
	}

	conn, err := pgx.Connect(ctx, cfg.connString)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	// The deferred call closes the connection, which also drops the
	// temporary table.
	defer conn.Close(ctx)

	if err := storeDocuments(ctx, conn, texts, vectors[:len(texts)]); err != nil {
		return err
	}

	body, err := nearest(ctx, conn, vectors[len(texts)])
	if err != nil {
		return err
	}

	fmt.Printf("Question: %s\n", question)
	fmt.Printf("Nearest document: %s\n", body)
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

- The [pgvector](https://github.com/pgvector/pgvector) documentation
  describes the vector types, distance operators, and indexes.
- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  repository documents every provider and option.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe to the cookbook.
