// Ellie's Postgres Cookbook
// Checking the health of the pgEdge RAG Server and listing its pipelines,
// using net/http.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
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

var baseURL = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")

// None of these endpoints calls a language model, but the health check
// contacts each provider, so allow it some time.
const timeout = 30 * time.Second

// get fetches a path from the server, and decodes the reply into out.
func get(client *http.Client, path string, out any) error {
	response, err := client.Get(baseURL + path)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}

	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("unexpected response: %.200s", body)
	}
	return nil
}

// --8<-- [end:config]

// --8<-- [start:live]
// checkLive checks that the server process is running. The /v1/live
// endpoint is cheap and calls nothing else, so it suits a frequent
// liveness probe.
func checkLive(client *http.Client) error {
	var body struct {
		Status string `json:"status"`
	}
	if err := get(client, "/v1/live", &body); err != nil {
		return err
	}
	if body.Status != "ok" {
		return fmt.Errorf("unexpected status %q", body.Status)
	}
	fmt.Println("Live: ok")
	return nil
}

// --8<-- [end:live]

// --8<-- [start:health]
// provider reports whether a language model provider answered the check.
type provider struct {
	Reachable bool   `json:"reachable"`
	Error     string `json:"error"`
}

// describe says in words whether the provider answered.
func (p provider) describe() string {
	if p.Reachable {
		return "reachable"
	}
	if p.Error == "" {
		return "unreachable (unknown)"
	}
	return "unreachable (" + p.Error + ")"
}

// checkHealth checks whether each pipeline can reach its language model
// providers. The /v1/health endpoint answers with HTTP 200 even when a
// provider is down, so the status field is the thing to check: it is
// "healthy" or "degraded". It prints the report, and returns whether the
// server is healthy.
func checkHealth(client *http.Client) (bool, error) {
	var body struct {
		Status    *string `json:"status"`
		Pipelines []struct {
			Name       string   `json:"name"`
			Embedding  provider `json:"embedding"`
			Completion provider `json:"completion"`
		} `json:"pipelines"`
	}
	if err := get(client, "/v1/health", &body); err != nil {
		return false, err
	}
	if body.Status == nil {
		return false, errors.New("unexpected response: missing status")
	}

	fmt.Printf("Health: %s\n", *body.Status)
	for _, p := range body.Pipelines {
		fmt.Printf("- %s: embedding %s, completion %s\n",
			p.Name, p.Embedding.describe(), p.Completion.describe())
	}
	return *body.Status == "healthy", nil
}

// --8<-- [end:health]

// --8<-- [start:pipelines]
// listPipelines lists the pipelines that the server offers, with their
// descriptions.
func listPipelines(client *http.Client) error {
	var body struct {
		Pipelines *[]struct {
			Name        string `json:"name"`
			Description string `json:"description"`
		} `json:"pipelines"`
	}
	if err := get(client, "/v1/pipelines", &body); err != nil {
		return err
	}
	if body.Pipelines == nil {
		return errors.New("unexpected response: missing pipelines")
	}

	fmt.Printf("Pipelines (%d):\n", len(*body.Pipelines))
	for _, p := range *body.Pipelines {
		description := p.Description
		if description == "" {
			description = "(no description)"
		}
		fmt.Printf("- %s: %s\n", p.Name, description)
	}
	return nil
}

// --8<-- [end:pipelines]

// --8<-- [start:main]
// run performs the checks and returns any error to the caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	if err := checkLive(client); err != nil {
		return err
	}
	healthy, err := checkHealth(client)
	if err != nil {
		return err
	}
	if err := listPipelines(client); err != nil {
		return err
	}

	// A degraded server still answers with HTTP 200, so report it with the
	// exit status.
	if !healthy {
		return errors.New("the server is not healthy")
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
