// Ellie's Postgres Cookbook
// Holding a conversation with the pgEdge RAG Server, using net/http.
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

// The second question does not say which version of the Acme Widget it
// means, so only the first question and its answer, which the model
// receives as history, settle that. The search uses only the current
// question, which is why this one still names the product.
var questions = []string{
	"How long does the Acme Widget 2.0 take to charge?",
	"And how many hours does the Acme Widget run for once it is charged?",
}

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeout = 300 * time.Second

// --8<-- [end:config]

// --8<-- [start:ask]
// message is one turn of a conversation. The role is "user" or
// "assistant".
type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
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

// ask sends a question and the conversation so far to the pipeline, and
// returns the answer. The server keeps no conversation between requests,
// so history lists the earlier messages, each with a role of user or
// assistant, in order.
func ask(client *http.Client, question string, history []message) (string, error) {
	payload, err := json.Marshal(map[string]any{
		"query":    question,
		"messages": history,
	})
	if err != nil {
		return "", err
	}

	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", err
	}

	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
	}

	// The answer is a pointer so that the program can tell a missing field
	// from an empty one.
	var result struct {
		Answer *string `json:"answer"`
	}
	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
		return "", fmt.Errorf("unexpected response: %.200s", body)
	}
	return *result.Answer, nil
}

// --8<-- [end:ask]

// --8<-- [start:converse]
// converse asks each question in turn, printing both sides of the
// conversation. After each answer, the question and the answer join the
// history that the next request carries.
func converse(client *http.Client) error {
	// A non-nil slice encodes as [] rather than null in the first request.
	history := []message{}
	for _, question := range questions {
		answer, err := ask(client, question, history)
		if err != nil {
			return err
		}
		fmt.Printf("You: %s\n", question)
		fmt.Printf("Assistant: %s\n", answer)
		history = append(history,
			message{Role: "user", Content: question},
			message{Role: "assistant", Content: answer})
	}
	return nil
}

// --8<-- [end:converse]

// --8<-- [start:main]
// main reports any error returned by converse() and exits with a non-zero
// status.
func main() {
	client := &http.Client{Timeout: timeout}
	if err := converse(client); err != nil {
		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
