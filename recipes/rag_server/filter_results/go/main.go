// Ellie's Postgres Cookbook
// Filtering the documents that the pgEdge RAG Server retrieves, using
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

const question = "How long does the Acme Widget take to charge?"

// The product to search, and the versions to ask about in turn. The
// question names no version, so only the filter tells the pipeline which
// documents to use.
const product = "Acme Widget"

var versions = []string{"1.0", "2.0"}

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeout = 300 * time.Second

// --8<-- [end:config]

// --8<-- [start:filter]
// condition compares one column of the pipeline's table with a value.
type condition struct {
	Column   string `json:"column"`
	Operator string `json:"operator"`
	Value    string `json:"value"`
}

// filter holds conditions that the server combines with Logic.
type filter struct {
	Logic      string      `json:"logic"`
	Conditions []condition `json:"conditions"`
}

// buildFilter returns the filter for a product and a version. The
// conditions are joined with AND, which is the default. The server passes
// the values to PostgreSQL as parameters, so they need no escaping.
func buildFilter(product, version string) filter {
	return filter{
		Logic: "AND",
		Conditions: []condition{
			{Column: "product", Operator: "=", Value: product},
			{Column: "version", Operator: "=", Value: version},
		},
	}
}

// --8<-- [end:filter]

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

// ask sends the question and the filter to the pipeline, and asks for the
// documents that the answer came from. It returns the decoded reply.
func ask(client *http.Client, question string, f filter) (*queryResponse, error) {
	payload, err := json.Marshal(map[string]any{
		"query":           question,
		"filter":          f,
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

// --8<-- [start:show]
// show prints the answer in a reply, and then the IDs of its sources.
func show(result *queryResponse) {
	ids := make([]string, 0, len(result.Sources))
	for _, s := range result.Sources {
		ids = append(ids, s.ID)
	}
	fmt.Printf("Answer:\n%s\n", *result.Answer)
	fmt.Printf("Sources: %s\n", strings.Join(ids, ", "))
}

// --8<-- [end:show]

// --8<-- [start:main]
// run asks the question once for each version and prints the replies,
// returning any error to the caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	fmt.Printf("Question: %s\n", question)
	for _, version := range versions {
		result, err := ask(client, question, buildFilter(product, version))
		if err != nil {
			return err
		}
		fmt.Println()
		fmt.Printf("Filter: product = %s, version = %s\n", product, version)
		show(result)
	}
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
