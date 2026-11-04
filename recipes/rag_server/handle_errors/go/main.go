// Ellie's Postgres Cookbook
// Handling errors from the pgEdge RAG Server by error code, using
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
	pipeline = envOr("RAG_PIPELINE", "cookbook")
)

// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
const missingPipeline = "no-such-pipeline"

// The server rejects both requests before it calls a language model, so
// they answer quickly.
const timeout = 30 * time.Second

// --8<-- [end:config]

// --8<-- [start:request]
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

// sendQuery sends a query to a pipeline. It returns an *apiError when the
// server replies with an error.
func sendQuery(client *http.Client, name, query string) error {
	payload, err := json.Marshal(map[string]string{"query": query})
	if err != nil {
		return err
	}

	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(name)
	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}

	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode == http.StatusOK {
		return nil
	}
	var e struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
	}
	return &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
}

// --8<-- [end:request]

// --8<-- [start:advise]
// advise returns advice for an error, chosen by the error code. Branch on
// the code rather than on the message, which is meant for people and may
// change; branch on the HTTP status only for the temporary failures that
// have no code worth handling individually.
func advise(e *apiError) string {
	switch {
	case e.Code == "PIPELINE_NOT_FOUND":
		return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
	case e.Code == "INVALID_REQUEST":
		return "Fix the request; the body must be JSON with a non-empty query."
	case e.Status == http.StatusServiceUnavailable, e.Status == http.StatusGatewayTimeout:
		return "The failure may be temporary, so retry the request later."
	default:
		return "This program does not handle " + e.Code + "."
	}
}

// --8<-- [end:advise]

// --8<-- [start:main]
// demonstrate sends one query that the server must refuse with the
// expected error code, and prints how the program handles the refusal.
// Any other outcome is a failure.
func demonstrate(client *http.Client, title, name, query, expected string) error {
	fmt.Println(title)
	err := sendQuery(client, name, query)

	var apiErr *apiError
	if !errors.As(err, &apiErr) {
		if err == nil {
			return errors.New("the request unexpectedly succeeded")
		}
		return err
	}

	fmt.Printf("  %s (HTTP %d): %s\n", apiErr.Code, apiErr.Status, apiErr.Message)
	fmt.Printf("  %s\n", advise(apiErr))
	if apiErr.Code != expected {
		return fmt.Errorf("expected %s, got %s", expected, apiErr.Code)
	}
	return nil
}

// run causes each error in turn and returns any unexpected outcome to the
// caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	if err := demonstrate(client, "Asking a pipeline that does not exist",
		missingPipeline, "Hello", "PIPELINE_NOT_FOUND"); err != nil {
		return err
	}
	return demonstrate(client, "Asking an empty question",
		pipeline, "", "INVALID_REQUEST")
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
