// Ellie's Postgres Cookbook
// Storing embeddings in PostgreSQL with pgvector and searching them, using
// the pgEdge Go LLM Library and pgx.
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
	"strconv"
	"strings"
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

// --8<-- [end:config]

// --8<-- [start:client]
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

// --8<-- [end:client]

// --8<-- [start:embed]
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

// --8<-- [end:embed]

// --8<-- [start:store]
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

// --8<-- [end:store]

// --8<-- [start:search]
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

// --8<-- [end:search]

// --8<-- [start:main]
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

	// Embed the documents and the question in one batch, before touching
	// the database, so a provider failure never leaves a half-filled table.
	vectors, err := embedTexts(ctx, client, append(texts, question))
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

// --8<-- [end:main]
