// Ellie's Postgres Cookbook
// Limiting the answers of the pgEdge RAG Server to each caller's own rows,
// using net/http.
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
	"errors"
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
	pipeline = envOr("RAG_PIPELINE", "cookbook_private")
)

const question = "What is the status of my warranty claim?"

// The callers to ask for. The fictional documents in the pipeline's table
// belong to these two people.
var callers = []string{"jane.doe@example.com", "john.smith@example.com"}

// The header in which the server expects a trusted proxy to put the claims
// of the caller. This is the server's default; the identity.claims_header
// setting changes it.
const claimsHeader = "X-Forwarded-Claims"

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeout = 300 * time.Second

// --8<-- [end:config]

// --8<-- [start:ask]
// source is a document that the answer came from.
type source struct {
	ID string `json:"id"`
}

// queryResponse holds the fields of the reply that the program uses. The
// answer is a pointer so that the program can tell a missing field from
// an empty one.
type queryResponse struct {
	Answer  *string  `json:"answer"`
	Sources []source `json:"sources"`
}

// apiError is returned when the RAG Server replies with an error. The
// reply has an HTTP status and a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
type apiError struct {
	Status  int
	Code    string
	Message string
}

func (e *apiError) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// ask sends the question to the pipeline on behalf of a caller, and asks
// for the documents that the answer came from. It returns the decoded
// reply. An empty subject sends no identity at all.
func ask(client *http.Client, subject string) (*queryResponse, error) {
	payload, err := json.Marshal(map[string]any{
		"query":           question,
		"include_sources": true,
	})
	if err != nil {
		return nil, err
	}

	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	if subject != "" {
		// The claims are a JSON object, which json.Marshal builds, so that
		// the subject needs no escaping.
		claims, err := json.Marshal(map[string]string{"sub": subject})
		if err != nil {
			return nil, err
		}
		request.Header.Set(claimsHeader, string(claims))
	}

	response, err := client.Do(request)
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
		var e struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
			return nil, fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
		}
		return nil, &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
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
// askAnonymously asks the question without an identity. The server must
// refuse with IDENTITY_REQUIRED, because it never falls back to the
// pipeline's own database role; any other outcome is a failure.
func askAnonymously(client *http.Client) error {
	fmt.Println()
	fmt.Println("Caller: (no identity)")

	_, err := ask(client, "")
	var apiErr *apiError
	if !errors.As(err, &apiErr) {
		if err == nil {
			return errors.New("the server answered without an identity; is identity.enabled set?")
		}
		return err
	}

	fmt.Printf("%s (HTTP %d)\n", apiErr.Code, apiErr.Status)
	if apiErr.Code != "IDENTITY_REQUIRED" {
		return fmt.Errorf("expected IDENTITY_REQUIRED, got %v", apiErr)
	}
	return nil
}

// run asks the question as each caller, and then without an identity,
// returning any error to the caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	fmt.Printf("Question: %s\n", question)
	for _, caller := range callers {
		result, err := ask(client, caller)
		if err != nil {
			return err
		}
		fmt.Println()
		fmt.Printf("Caller: %s\n", caller)
		show(result)
	}
	return askAnonymously(client)
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
