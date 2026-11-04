// Ellie's Postgres Cookbook
// Asking the pgEdge RAG Server a question, using net/http.
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
// queryResponse holds the fields of the reply that the program uses; a
// pointer lets the program tell a missing field from a zero value.
type queryResponse struct {
	Answer     *string `json:"answer"`
	TokensUsed *int    `json:"tokens_used"`
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

// ask sends the question to the pipeline, and returns the answer with the
// number of tokens the request used.
func ask(client *http.Client, question string) (string, int, error) {
	payload, err := json.Marshal(map[string]any{"query": question})
	if err != nil {
		return "", 0, err
	}

	// PathEscape escapes any character in the pipeline name that is not
	// safe in a URL path.
	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
	if err != nil {
		return "", 0, err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", 0, err
	}

	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode != http.StatusOK {
		return "", 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
	}

	var result queryResponse
	if err := json.Unmarshal(body, &result); err != nil ||
		result.Answer == nil || result.TokensUsed == nil {
		return "", 0, fmt.Errorf("unexpected response: %.200s", body)
	}
	return *result.Answer, *result.TokensUsed, nil
}

// --8<-- [end:ask]

// --8<-- [start:main]
// run asks the question and prints the reply, returning any error to the
// caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	answer, tokensUsed, err := ask(client, question)
	if err != nil {
		return err
	}

	fmt.Printf("Question: %s\n", question)
	fmt.Printf("Answer:\n%s\n", answer)
	fmt.Printf("Tokens used: %d\n", tokensUsed)
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
