// Ellie's Postgres Cookbook
// Preparing documents for the pgEdge RAG Server: embedding them with
// Ollama and storing them in a pgvector table, using net/http and pgx.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
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

var (
	ollamaURL  = strings.TrimRight(envOr("OLLAMA_URL", "http://localhost:11434"), "/")
	embedModel = envOr("EMBED_MODEL", "nomic-embed-text")
)

// This recipe uses its own table, so that it never disturbs the table that
// a running pipeline reads.
const table = "cookbook_prepare_data"

// document is a row to store. The text is fictional; in a real
// application the documents come from your own data.
type document struct {
	ID      int
	Title   string
	Content string
}

var documents = []document{
	{1, "Charging the Acme Gadget",
		"The Acme Gadget charges through its USB-C port. A full charge takes " +
			"two hours, and a fully charged Acme Gadget runs for ten hours."},
	{2, "Resetting the Acme Gadget",
		"To reset the Acme Gadget to its factory settings, hold down the " +
			"power button for eight seconds until the status light flashes red."},
	{3, "Warranty for the Acme Gadget",
		"The Acme Gadget comes with a two-year warranty that covers " +
			"manufacturing defects but not accidental damage."},
}

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
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
	return u.String()
}

// --8<-- [end:config]

// --8<-- [start:embed]
// embed asks Ollama for the embedding of each text, in the same order.
func embed(texts []string) ([][]float32, error) {
	// The embed endpoint accepts a list of texts, so one request embeds
	// every document.
	payload, err := json.Marshal(map[string]any{"model": embedModel, "input": texts})
	if err != nil {
		return nil, err
	}

	client := &http.Client{Timeout: 300 * time.Second}
	response, err := client.Post(ollamaURL+"/api/embed", "application/json", bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ollama returned HTTP %d: %.200s", response.StatusCode, body)
	}

	var result struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("unexpected response from ollama: %w", err)
	}
	if len(result.Embeddings) != len(texts) {
		return nil, fmt.Errorf("expected %d embeddings, got %d", len(texts), len(result.Embeddings))
	}
	return result.Embeddings, nil
}

// --8<-- [end:embed]

// --8<-- [start:table]
// createTable creates the table, replacing any earlier copy. The vector
// column must have the same number of dimensions as the embedding model.
func createTable(ctx context.Context, tx pgx.Tx, dimensions int) error {
	if _, err := tx.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "DROP TABLE IF EXISTS "+table); err != nil {
		return err
	}
	// The table name is a constant and the dimensions are an integer, so
	// building them into the statement is safe; a statement cannot take
	// either as a parameter.
	_, err := tx.Exec(ctx, `
		CREATE TABLE `+table+` (
			id        integer PRIMARY KEY,
			title     text NOT NULL,
			content   text NOT NULL,
			embedding vector(`+strconv.Itoa(dimensions)+`) NOT NULL
		)`)
	return err
}

// --8<-- [end:table]

// --8<-- [start:insert]
// vectorText formats an embedding as the text that pgvector reads, such as
// '[0.1,0.2,0.3]'.
func vectorText(embedding []float32) string {
	parts := make([]string, len(embedding))
	for i, value := range embedding {
		parts[i] = strconv.FormatFloat(float64(value), 'g', -1, 32)
	}
	return "[" + strings.Join(parts, ",") + "]"
}

// insertDocuments stores each document with its embedding.
func insertDocuments(ctx context.Context, tx pgx.Tx, embeddings [][]float32) error {
	for i, doc := range documents {
		// The cast tells the server how to interpret the text parameter.
		_, err := tx.Exec(ctx,
			"INSERT INTO "+table+" (id, title, content, embedding) VALUES ($1, $2, $3, $4::vector)",
			doc.ID, doc.Title, doc.Content, vectorText(embeddings[i]))
		if err != nil {
			return err
		}
	}
	return nil
}

// --8<-- [end:insert]

// --8<-- [start:verify]
// describeTable returns the number of rows, and the number of dimensions
// of their embeddings.
func describeTable(ctx context.Context, conn *pgx.Conn) (rows, dimensions int, err error) {
	err = conn.QueryRow(ctx,
		"SELECT count(*), max(vector_dims(embedding)) FROM "+table,
	).Scan(&rows, &dimensions)
	return rows, dimensions, err
}

// --8<-- [end:verify]

// --8<-- [start:cleanup]
// dropTable removes the table. A real application keeps it, so that the
// RAG Server can read it.
func dropTable(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS "+table)
	return err
}

// --8<-- [end:cleanup]

// --8<-- [start:main]
// store creates the table and inserts the documents in one transaction.
func store(ctx context.Context, conn *pgx.Conn, embeddings [][]float32) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	// Rollback does nothing after a successful commit, so the deferred
	// call only matters when a step fails.
	defer tx.Rollback(ctx)

	if err := createTable(ctx, tx, len(embeddings[0])); err != nil {
		return err
	}
	if err := insertDocuments(ctx, tx, embeddings); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// run embeds the documents, stores them, and reports what the table
// holds, returning any error to the caller.
func run(ctx context.Context) (err error) {
	texts := make([]string, len(documents))
	for i, doc := range documents {
		texts[i] = doc.Content
	}
	embeddings, err := embed(texts)
	if err != nil {
		return fmt.Errorf("embedding failed: %w", err)
	}
	fmt.Printf("Embedded %d documents with %s\n", len(embeddings), embedModel)

	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	defer conn.Close(ctx)

	// Remove the table whether or not a step failed, and report a failure
	// to remove it unless an earlier error is already being returned.
	defer func() {
		if dropErr := dropTable(ctx, conn); dropErr != nil && err == nil {
			err = dropErr
		}
	}()

	if err := store(ctx, conn, embeddings); err != nil {
		return fmt.Errorf("storing the documents failed: %w", err)
	}

	rows, dimensions, err := describeTable(ctx, conn)
	if err != nil {
		return fmt.Errorf("query failed: %w", err)
	}
	fmt.Printf("Stored %d rows with %d-dimension embeddings in %s\n", rows, dimensions, table)
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
