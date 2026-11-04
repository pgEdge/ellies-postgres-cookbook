// Ellie's Postgres Cookbook
// Letting a model query the database through a tool, using the pgEdge Go
// LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"regexp"
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

// llmSettings reads the language model settings from the environment.
// An empty LLM_BASE_URL means that the library uses the provider's own
// default endpoint, and an empty LLM_API_KEY means that no key is sent.
func llmSettings() (provider string, opts llm.Options) {
	provider = envOr("LLM_PROVIDER", "ollama")
	opts = llm.Options{
		Model:   envOr("LLM_MODEL", "qwen2.5:1.5b"),
		APIKey:  os.Getenv("LLM_API_KEY"),
		BaseURL: os.Getenv("LLM_BASE_URL"),
	}
	return provider, opts
}

// --8<-- [end:config]

// --8<-- [start:client]
// newClient builds a chat client from the settings in the environment.
func newClient() (llm.Client, error) {
	provider, opts := llmSettings()

	// The default of five retries with a two second pause that doubles
	// each time suits a busy cloud service, but makes a mistyped address
	// take a minute to report. Two short retries still ride out a
	// momentary failure.
	opts.Retry = llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 500 * time.Millisecond,
	}

	client, err := llm.NewClient(provider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the %s client failed: %w", provider, err)
	}
	return client, nil
}

// --8<-- [end:client]

// --8<-- [start:connect]
// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:tool]
// countTypesTool describes the one thing the model may ask for. The
// model sees only this name, this description, and this JSON Schema; it
// never sees the SQL that the program runs, and it cannot write any.
var countTypesTool = llm.Tool{
	Name: "count_types",
	Description: "Counts the data types in the PostgreSQL database " +
		"that have the given name.",
	InputSchema: json.RawMessage(`{
		"type": "object",
		"properties": {
			"name": {
				"type": "string",
				"description": "The name of a data type, such as int4."
			}
		},
		"required": ["name"]
	}`),
}

// --8<-- [end:tool]

// --8<-- [start:execute]
// typeNamePattern limits the argument to the characters that appear in
// built-in type names, which rejects anything odd the model sends.
var typeNamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{1,63}$`)

// countTypes runs the tool for the model, and returns the type name that
// the model asked about with the count as text. The model controls only
// the value of $1; the SQL text is fixed, and pgx sends the value
// separately.
func countTypes(ctx context.Context, conn *pgx.Conn, call *llm.ToolUse) (string, string, error) {
	if call.Name != countTypesTool.Name {
		return "", "", fmt.Errorf("the model called an unknown tool: %q", call.Name)
	}

	// A small model sometimes sends malformed or incomplete arguments,
	// so check them before they reach the database.
	var args struct {
		TypeName string `json:"name"`
	}
	if err := json.Unmarshal(call.Input, &args); err != nil {
		return "", "", fmt.Errorf("the model sent unusable arguments %s: %w", call.Input, err)
	}
	if !typeNamePattern.MatchString(args.TypeName) {
		return "", "", fmt.Errorf("the model sent an invalid type name %q in %s", args.TypeName, call.Input)
	}

	var count int64
	err := conn.QueryRow(ctx,
		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
		args.TypeName,
	).Scan(&count)
	if err != nil {
		return "", "", fmt.Errorf("query failed: %w", err)
	}
	return args.TypeName, fmt.Sprintf("%d", count), nil
}

// --8<-- [end:execute]

// --8<-- [start:ask]
// answerWithTool asks the question, runs the tool that the model calls,
// and returns the type name from the tool call with the model's final
// answer.
func answerWithTool(ctx context.Context, client llm.Client, conn *pgx.Conn, question string) (string, string, error) {
	messages := []llm.Message{llm.UserText(question)}
	tools := []llm.Tool{countTypesTool}

	// Force the first reply to be a call to count_types. Providers with a
	// native tool choice setting obey it; Ollama has none, so the check
	// below is what guarantees that a tool was called.
	first, err := client.Chat(ctx, llm.ChatRequest{
		Messages: messages,
		Tools:    tools,
		ToolChoice: &llm.ToolChoice{
			Mode: llm.ToolChoiceSpecific,
			Name: countTypesTool.Name,
		},
	})
	if err != nil {
		return "", "", fmt.Errorf("first request failed: %w", err)
	}

	var call *llm.ToolUse
	for _, block := range first.Content {
		if block.Type == llm.BlockToolUse {
			call = block.ToolUse
			break
		}
	}
	if call == nil {
		return "", "", errors.New("the model did not call the tool")
	}

	name, result, err := countTypes(ctx, conn, call)
	if err != nil {
		return "", "", err
	}

	// Send the whole conversation back: the question, the model's own
	// tool call, and the result, which refers to the call by its ID.
	messages = append(messages,
		llm.Message{Role: llm.RoleAssistant, Content: first.Content},
		llm.ToolResultMessage(call.ID, result, false),
	)

	// Some providers require the tools to be listed while the history
	// contains tool calls, so list them again but forbid another call.
	final, err := client.Chat(ctx, llm.ChatRequest{
		Messages:   messages,
		Tools:      tools,
		ToolChoice: &llm.ToolChoice{Mode: llm.ToolChoiceNone},
	})
	if err != nil {
		return "", "", fmt.Errorf("second request failed: %w", err)
	}

	var text strings.Builder
	for _, block := range final.Content {
		if block.Type == llm.BlockText {
			text.WriteString(block.Text)
		}
	}
	answer := strings.TrimSpace(text.String())
	if answer == "" {
		return "", "", errors.New("the model gave no final answer")
	}
	return name, answer, nil
}

// --8<-- [end:ask]

// --8<-- [start:main]
// run connects, asks the question, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	client, err := newClient()
	if err != nil {
		return err
	}

	name, answer, err := answerWithTool(ctx, client, conn,
		"How many data types named int4 are there in the database?")
	if err != nil {
		return err
	}

	fmt.Printf("Tool call: count_types(%s)\n", name)
	fmt.Printf("Answer: %s\n", answer)
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
