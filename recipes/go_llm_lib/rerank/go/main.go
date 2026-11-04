// Ellie's Postgres Cookbook
// Reranking search results from PostgreSQL with a Voyage rerank model,
// using the pgEdge Go LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
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

// --8<-- [end:config]

// --8<-- [start:client]
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

// --8<-- [end:client]

// --8<-- [start:candidates]
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

// --8<-- [end:candidates]

// --8<-- [start:rerank]
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

// --8<-- [end:rerank]

// --8<-- [start:main]
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

// --8<-- [end:main]
