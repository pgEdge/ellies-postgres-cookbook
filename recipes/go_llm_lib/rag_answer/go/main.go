// Ellie's Postgres Cookbook
// Answering a question from your own data: retrieve the most relevant rows
// with pgvector and pass them to a chat model, using the pgEdge Go LLM
// Library and pgx.
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
	llmModel      string
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
		llmModel:      envOr("LLM_MODEL", "qwen2.5:1.5b"),
		embedProvider: envOr("EMBED_PROVIDER", "ollama"),
		embedModel:    envOr("EMBED_MODEL", "nomic-embed-text"),
		apiKey:        os.Getenv("LLM_API_KEY"),
		baseURL:       os.Getenv("LLM_BASE_URL"),
		connString:    u.String(),
	}
}

// --8<-- [end:config]

// --8<-- [start:client]
// retry keeps the wait short when a provider is unreachable.
var retry = llm.RetryConfig{
	MaxRetries:     2,
	InitialBackoff: 200 * time.Millisecond,
	MaxBackoff:     time.Second,
}

// newClients builds one client for chat and one for embeddings. The API
// key and base URL apply to the chat client, and to the embedding client
// only when both use the same provider; otherwise the library uses the
// embedding provider's own defaults and reads its key from the provider's
// own environment variable.
func newClients(cfg config) (chat, embed llm.Client, err error) {
	chat, err = llm.NewClient(cfg.llmProvider, llm.Options{
		Model:   cfg.llmModel,
		APIKey:  cfg.apiKey,
		BaseURL: cfg.baseURL,
		// Keep the answer short, which also keeps the request quick.
		MaxTokens:   llm.Int(150),
		Temperature: llm.Float(0),
		Retry:       retry,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("creating the chat client failed: %w", err)
	}

	embedOpts := llm.Options{Model: cfg.embedModel, Retry: retry}
	if cfg.embedProvider == cfg.llmProvider {
		embedOpts.APIKey = cfg.apiKey
		embedOpts.BaseURL = cfg.baseURL
	}
	embed, err = llm.NewClient(cfg.embedProvider, embedOpts)
	if err != nil {
		return nil, nil, fmt.Errorf("creating the embedding client failed: %w", err)
	}
	return chat, embed, nil
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
// storeFacts creates a temporary table whose vector column matches the
// size of the embeddings, and inserts one row per fact. The id of a row is
// its position in the list, starting at 1.
func storeFacts(ctx context.Context, conn *pgx.Conn, facts []string, vectors [][]float64) error {
	if _, err := conn.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
		return fmt.Errorf("creating the extension failed: %w", err)
	}

	// The dimension count is an integer taken from the embedding, so it is
	// safe to format into the statement; SQL cannot take it as a parameter.
	create := fmt.Sprintf(
		"CREATE TEMPORARY TABLE facts (id int PRIMARY KEY, body text, embedding vector(%d))",
		len(vectors[0]))
	if _, err := conn.Exec(ctx, create); err != nil {
		return fmt.Errorf("creating the table failed: %w", err)
	}

	for i, fact := range facts {
		_, err := conn.Exec(ctx,
			"INSERT INTO facts (id, body, embedding) VALUES ($1, $2, $3::vector)",
			i+1, fact, vectorLiteral(vectors[i]))
		if err != nil {
			return fmt.Errorf("insert failed: %w", err)
		}
	}
	return nil
}

// --8<-- [end:store]

// --8<-- [start:retrieve]
// fact is one row returned by the search.
type fact struct {
	id   int
	body string
}

// retrieve returns the facts nearest to the question, closest first, using
// the cosine distance operator (<=>).
func retrieve(ctx context.Context, conn *pgx.Conn, question []float64, limit int) ([]fact, error) {
	rows, err := conn.Query(ctx,
		"SELECT id, body FROM facts ORDER BY embedding <=> $1::vector LIMIT $2",
		vectorLiteral(question), limit)
	if err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	defer rows.Close()

	var found []fact
	for rows.Next() {
		var f fact
		if err := rows.Scan(&f.id, &f.body); err != nil {
			return nil, fmt.Errorf("reading a row failed: %w", err)
		}
		found = append(found, f)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}
	return found, nil
}

// --8<-- [end:retrieve]

// --8<-- [start:answer]
// answer asks the chat model the question, giving it the retrieved facts
// as context and telling it to use nothing else.
func answer(ctx context.Context, client llm.Client, question string, retrieved []fact) (string, error) {
	var prompt strings.Builder
	prompt.WriteString("Context:\n")
	for _, f := range retrieved {
		fmt.Fprintf(&prompt, "- %s\n", f.body)
	}
	fmt.Fprintf(&prompt, "\nQuestion: %s", question)

	resp, err := client.Chat(ctx, llm.ChatRequest{
		SystemPrompt: "Answer the question in one short sentence, using only " +
			"the context. If the context does not contain the answer, say " +
			"that you do not know.",
		Messages: []llm.Message{llm.UserText(prompt.String())},
	})
	if err != nil {
		return "", fmt.Errorf("chat request failed: %w", err)
	}

	// A response is a list of content blocks; join the text blocks.
	var text strings.Builder
	for _, block := range resp.Content {
		if block.Type == llm.BlockText {
			text.WriteString(block.Text)
		}
	}
	// Put the answer on one line, whatever whitespace the model used.
	reply := strings.Join(strings.Fields(text.String()), " ")
	if reply == "" {
		return "", fmt.Errorf("the model returned no text")
	}
	return reply, nil
}

// --8<-- [end:answer]

// --8<-- [start:main]
// run embeds the facts and the question, retrieves the two nearest facts,
// and prints the model's answer with the ids of the facts it was given.
func run(ctx context.Context) error {
	cfg := loadConfig()

	chat, embed, err := newClients(cfg)
	if err != nil {
		return err
	}

	facts := []string{
		"The Zephyr Kettle comes with a three-year warranty that covers manufacturing defects.",
		"The Zephyr Kettle holds 1.7 litres of water.",
		"The Zephyr Kettle is available in matte black, white, and copper.",
		"The Zephyr Kettle boils a full load in about three minutes.",
		"Descale the Zephyr Kettle once a month with citric acid.",
	}
	question := "How long is the warranty on the Zephyr Kettle?"

	inputs := make([]string, 0, len(facts)+1)
	inputs = append(inputs, facts...)
	inputs = append(inputs, question)

	// Embed the facts and the question in one batch, before touching the
	// database, so a provider failure never leaves a half-filled table.
	vectors, err := embedTexts(ctx, embed, inputs)
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

	if err := storeFacts(ctx, conn, facts, vectors[:len(facts)]); err != nil {
		return err
	}

	found, err := retrieve(ctx, conn, vectors[len(facts)], 2)
	if err != nil {
		return err
	}

	reply, err := answer(ctx, chat, question, found)
	if err != nil {
		return err
	}

	ids := make([]string, len(found))
	for i, f := range found {
		ids[i] = strconv.Itoa(f.id)
	}
	fmt.Printf("Question: %s\n", question)
	fmt.Printf("Answer: %s\n", reply)
	fmt.Printf("Sources: %s\n", strings.Join(ids, ", "))
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
