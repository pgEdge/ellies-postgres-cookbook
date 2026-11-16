# Reranking Search Results

This recipe shows how a Go program improves the order of search results
from PostgreSQL by reranking them with a model, using the pgEdge Go LLM
Library. A database query finds candidate rows quickly but orders them
crudely; a rerank model reads the query and each candidate together, and
scores how well each candidate answers the query. The example is written in
Go only, because the library is a Go package.

The example program stores five short help articles in a temporary table,
retrieves the four that mention passwords with a keyword search, and asks the
model to rank them for the query "How do I reset my password?". It prints the
three best candidates with their scores. The following sample is illustrative:
the scores are examples, not real results, and they vary, but the article about
resetting a password should come first. The scale of the scores depends on the
model, so compare them only within one response:

```text
Query: How do I reset my password?
1. [0.93] To reset a forgotten password, choose Forgot password on the sign-in page and follow the link in the email.
2. [0.41] Two-factor authentication adds a second check on top of your password.
3. [0.36] A password manager stores your passwords in an encrypted vault.
```

## Preparing the Ingredients

Voyage AI is the only provider in the library that supports reranking, so
this recipe needs a Voyage API key; it does not run against Ollama. The
program reads the key from the `VOYAGE_API_KEY` environment variable, and
the cookbook's test script skips the recipe when that variable is unset.
The following command sets the key:

```bash
export VOYAGE_API_KEY=your-api-key
```

The example uses the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
for the rerank request and [pgx](https://github.com/jackc/pgx) to talk to
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
package registers every provider that the library supports, including
Voyage. The following code shows the imports:

```go
import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
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
[first recipe](../postgresql/connect_and_query.md). The library reads the
Voyage key from `VOYAGE_API_KEY` by itself. When `LLM_PROVIDER` is
`voyage`, the program also honours `LLM_API_KEY` and `LLM_BASE_URL`, which
is useful for a proxy or a test server. The following code shows how the
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

// config holds the settings that the program reads from the environment.
type config struct {
	// apiKey and baseURL come from LLM_API_KEY and LLM_BASE_URL, and are
	// used only when LLM_PROVIDER is voyage. Otherwise the library reads
	// the key from VOYAGE_API_KEY and uses the Voyage endpoint.
	apiKey     string
	baseURL    string
	connString string
}

// loadConfig reads the LLM_* and PG* environment variables. An empty
// variable counts as unset.
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

	cfg := config{connString: u.String()}
	if envOr("LLM_PROVIDER", "ollama") == "voyage" {
		cfg.apiKey = os.Getenv("LLM_API_KEY")
		cfg.baseURL = os.Getenv("LLM_BASE_URL")
	}
	return cfg
}

```

## Creating the Client

The program builds a client for the `voyage` provider with `llm.NewClient`,
and selects the `rerank-2.5` model in the `llm.Options` value. Other
providers return an error from `Rerank`. The retry settings keep the wait
short when the service is unreachable. The following code builds the
client:

```go
// newRerankClient builds a Voyage client. Voyage is the only provider in
// the library that supports reranking; the other providers return an
// error from Rerank.
func newRerankClient(cfg config) (llm.Client, error) {
	client, err := llm.NewClient("voyage", llm.Options{
		Model:   "rerank-2.5",
		APIKey:  cfg.apiKey,
		BaseURL: cfg.baseURL,
		// Retry briefly, so that an unreachable server fails quickly.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
			MaxBackoff:     time.Second,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("creating the rerank client failed: %w", err)
	}
	return client, nil
}

```

## Retrieving the Candidates

The program creates a `TEMPORARY` table, which disappears when the
connection closes so that the example can run repeatedly, and loads five
articles into it. A keyword search with `ILIKE` then selects the candidates.
The search is cheap but crude, and it returns the candidates in id order
rather than in order of relevance. The following code creates the table and
runs the search:

```go
// loadCandidates creates a temporary table of articles and returns the
// bodies of the candidates that a cheap keyword search finds. Retrieval
// like this is fast but crude, and it orders the candidates by id rather
// than by how well they answer the query.
func loadCandidates(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	_, err := conn.Exec(ctx,
		"CREATE TEMPORARY TABLE articles (id int PRIMARY KEY, body text)")
	if err != nil {
		return nil, fmt.Errorf("creating the table failed: %w", err)
	}

	articles := []string{
		"Passwords must be at least twelve characters long.",
		"To reset a forgotten password, choose Forgot password on the sign-in page and follow the link in the email.",
		"A password manager stores your passwords in an encrypted vault.",
		"Billing questions can be sent to the support team.",
		"Two-factor authentication adds a second check on top of your password.",
	}
	for i, body := range articles {
		_, err := conn.Exec(ctx,
			"INSERT INTO articles (id, body) VALUES ($1, $2)", i+1, body)
		if err != nil {
			return nil, fmt.Errorf("insert failed: %w", err)
		}
	}

	rows, err := conn.Query(ctx,
		"SELECT body FROM articles WHERE body ILIKE '%password%' ORDER BY id")
	if err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	defer rows.Close()

	var candidates []string
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			return nil, fmt.Errorf("reading a row failed: %w", err)
		}
		candidates = append(candidates, body)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	return candidates, nil
}

```

## Reranking the Candidates

The `Rerank` method takes the query and the candidate texts in an
`llm.RerankRequest`, and `TopK` limits the number of results. The results
come back in descending order of relevance score. Each result holds the
`Index` of the candidate in the slice that the program sent, rather than
the text, so the program looks the text up by index. The following code
sends the request:

```go
// rerank asks the model to order the candidates by relevance to the query.
// TopK limits the number of results; each result carries the index of the
// candidate in the slice that was sent, and a relevance score.
func rerank(ctx context.Context, client llm.Client, query string, candidates []string, topK int) ([]llm.RerankResult, error) {
	resp, err := client.Rerank(ctx, llm.RerankRequest{
		Query:     query,
		Documents: candidates,
		TopK:      llm.Int(topK),
	})
	if err != nil {
		return nil, fmt.Errorf("rerank failed: %w", err)
	}
	if len(resp.Results) == 0 {
		return nil, fmt.Errorf("the model returned no results")
	}
	// Check every index before the caller uses it to look up a candidate.
	for _, r := range resp.Results {
		if r.Index < 0 || r.Index >= len(candidates) {
			return nil, fmt.Errorf("the model returned an invalid index %d", r.Index)
		}
	}
	return resp.Results, nil
}

```

## Handling Errors and Closing the Connection

The `run` function ties the steps together and prints each result with its
rank and score. The deferred call closes the connection, which also drops
the temporary table. The `main` function reports any error on `stderr` and
exits with a non-zero status. The following code shows both functions:

```go
// run retrieves the candidates, reranks them, and prints them in order
// with their scores.
func run(ctx context.Context) error {
	cfg := loadConfig()

	client, err := newRerankClient(cfg)
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

	query := "How do I reset my password?"
	candidates, err := loadCandidates(ctx, conn)
	if err != nil {
		return err
	}

	results, err := rerank(ctx, client, query, candidates, 3)
	if err != nil {
		return err
	}

	fmt.Printf("Query: %s\n", query)
	for rank, r := range results {
		fmt.Printf("%d. [%.2f] %s\n", rank+1, r.RelevanceScore, candidates[r.Index])
	}
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

The following commands run the example against a local PostgreSQL server:

```bash
export PGHOST=localhost PGUSER=postgres
export VOYAGE_API_KEY=your-api-key
cd recipes/go_llm_lib/rerank/go
go run .
```

## Viewing the Complete Program

The following code shows the complete program:

```go
// Ellie's Postgres Cookbook
// Reranking search results from PostgreSQL with a Voyage rerank model,
// using the pgEdge Go LLM Library and pgx.
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
	// apiKey and baseURL come from LLM_API_KEY and LLM_BASE_URL, and are
	// used only when LLM_PROVIDER is voyage. Otherwise the library reads
	// the key from VOYAGE_API_KEY and uses the Voyage endpoint.
	apiKey     string
	baseURL    string
	connString string
}

// loadConfig reads the LLM_* and PG* environment variables. An empty
// variable counts as unset.
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

	cfg := config{connString: u.String()}
	if envOr("LLM_PROVIDER", "ollama") == "voyage" {
		cfg.apiKey = os.Getenv("LLM_API_KEY")
		cfg.baseURL = os.Getenv("LLM_BASE_URL")
	}
	return cfg
}


// newRerankClient builds a Voyage client. Voyage is the only provider in
// the library that supports reranking; the other providers return an
// error from Rerank.
func newRerankClient(cfg config) (llm.Client, error) {
	client, err := llm.NewClient("voyage", llm.Options{
		Model:   "rerank-2.5",
		APIKey:  cfg.apiKey,
		BaseURL: cfg.baseURL,
		// Retry briefly, so that an unreachable server fails quickly.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
			MaxBackoff:     time.Second,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("creating the rerank client failed: %w", err)
	}
	return client, nil
}


// loadCandidates creates a temporary table of articles and returns the
// bodies of the candidates that a cheap keyword search finds. Retrieval
// like this is fast but crude, and it orders the candidates by id rather
// than by how well they answer the query.
func loadCandidates(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	_, err := conn.Exec(ctx,
		"CREATE TEMPORARY TABLE articles (id int PRIMARY KEY, body text)")
	if err != nil {
		return nil, fmt.Errorf("creating the table failed: %w", err)
	}

	articles := []string{
		"Passwords must be at least twelve characters long.",
		"To reset a forgotten password, choose Forgot password on the sign-in page and follow the link in the email.",
		"A password manager stores your passwords in an encrypted vault.",
		"Billing questions can be sent to the support team.",
		"Two-factor authentication adds a second check on top of your password.",
	}
	for i, body := range articles {
		_, err := conn.Exec(ctx,
			"INSERT INTO articles (id, body) VALUES ($1, $2)", i+1, body)
		if err != nil {
			return nil, fmt.Errorf("insert failed: %w", err)
		}
	}

	rows, err := conn.Query(ctx,
		"SELECT body FROM articles WHERE body ILIKE '%password%' ORDER BY id")
	if err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	defer rows.Close()

	var candidates []string
	for rows.Next() {
		var body string
		if err := rows.Scan(&body); err != nil {
			return nil, fmt.Errorf("reading a row failed: %w", err)
		}
		candidates = append(candidates, body)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	return candidates, nil
}


// rerank asks the model to order the candidates by relevance to the query.
// TopK limits the number of results; each result carries the index of the
// candidate in the slice that was sent, and a relevance score.
func rerank(ctx context.Context, client llm.Client, query string, candidates []string, topK int) ([]llm.RerankResult, error) {
	resp, err := client.Rerank(ctx, llm.RerankRequest{
		Query:     query,
		Documents: candidates,
		TopK:      llm.Int(topK),
	})
	if err != nil {
		return nil, fmt.Errorf("rerank failed: %w", err)
	}
	if len(resp.Results) == 0 {
		return nil, fmt.Errorf("the model returned no results")
	}
	// Check every index before the caller uses it to look up a candidate.
	for _, r := range resp.Results {
		if r.Index < 0 || r.Index >= len(candidates) {
			return nil, fmt.Errorf("the model returned an invalid index %d", r.Index)
		}
	}
	return resp.Results, nil
}


// run retrieves the candidates, reranks them, and prints them in order
// with their scores.
func run(ctx context.Context) error {
	cfg := loadConfig()

	client, err := newRerankClient(cfg)
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

	query := "How do I reset my password?"
	candidates, err := loadCandidates(ctx, conn)
	if err != nil {
		return err
	}

	results, err := rerank(ctx, client, query, candidates, 3)
	if err != nil {
		return err
	}

	fmt.Printf("Query: %s\n", query)
	for rank, r := range results {
		fmt.Printf("%d. [%.2f] %s\n", rank+1, r.RelevanceScore, candidates[r.Index])
	}
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

- The [Answering Questions from Your Own Data](rag_answer.md) recipe
  retrieves rows with vector search; reranking the retrieved rows before
  they reach the chat model often improves the answer.
- The [Voyage AI documentation](https://docs.voyageai.com/docs/reranker)
  describes the rerank models and their limits.
- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  repository documents every provider and option.
