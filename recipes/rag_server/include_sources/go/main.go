// Ellie's Postgres Cookbook
// Showing the sources of an answer from the pgEdge RAG Server, using
// net/http.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
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
	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
	pipeline = envOr("RAG_PIPELINE", "cookbook")
)

const question = "How long does the Acme Widget 2.0 take to charge?"

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeout = 300 * time.Second

// --8<-- [end:config]

// --8<-- [start:ask]
// source is a document that the answer came from.
type source struct {
	ID      string  `json:"id"`
	Content string  `json:"content"`
	Score   float64 `json:"score"`
}

// queryResponse holds the fields of the reply that the program uses. The
// answer is a pointer so that the program can tell a missing field from
// an empty one.
type queryResponse struct {
	Answer  *string  `json:"answer"`
	Sources []source `json:"sources"`
}

// errorText describes an error response, which carries a JSON body of the
// form {"error": {"code": "...", "message": "..."}}.
func errorText(body []byte) string {
	var e struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
		return e.Error.Code + ": " + e.Error.Message
	}
	return strings.TrimSpace(string(body))
}

// ask sends the question to the pipeline, and asks for the documents that
// the answer came from. It returns the decoded reply.
func ask(client *http.Client, question string) (*queryResponse, error) {
	payload, err := json.Marshal(map[string]any{
		"query":           question,
		"include_sources": true,
	})
	if err != nil {
		return nil, err
	}

	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
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
		return nil, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
	}

	var result queryResponse
	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
		return nil, fmt.Errorf("unexpected response: %.200s", body)
	}
	return &result, nil
}

// --8<-- [end:ask]

// --8<-- [start:sources]
// describeSource returns one line for a source: its ID and the start of
// its text.
func describeSource(s source) string {
	// Collapse any line breaks, and shorten long text for display.
	content := strings.Join(strings.Fields(s.Content), " ")
	if runes := []rune(content); len(runes) > 60 {
		content = string(runes[:57]) + "..."
	}
	return fmt.Sprintf("- %s: %s", s.ID, content)
}

// printSources prints the sources in a reply, in the order that the server returns them.
func printSources(result *queryResponse) {
	// The server leaves out the sources array, without an error, when the
	// pipeline does not set allow_include_sources.
	if len(result.Sources) == 0 {
		fmt.Println("No sources were returned. Does the pipeline set allow_include_sources?")
		return
	}

	fmt.Printf("Sources (%d):\n", len(result.Sources))
	for _, s := range result.Sources {
		fmt.Println(describeSource(s))
	}
}

// --8<-- [end:sources]

// --8<-- [start:main]
// run asks the question and prints the reply, returning any error to the
// caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	result, err := ask(client, question)
	if err != nil {
		return err
	}

	fmt.Printf("Question: %s\n", question)
	fmt.Printf("Answer:\n%s\n", *result.Answer)
	printSources(result)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
