// Ellie's Postgres Cookbook
// Running read-only queries through the pgEdge Postgres MCP Server, using
// net/http.
//
// These examples are for pgEdge Postgres MCP Server 1.1.0.
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
	baseURL = strings.TrimRight(envOr("MCP_URL", "http://localhost:8080"), "/")
	token   = os.Getenv("MCP_TOKEN")
)

const timeout = 30 * time.Second

// shorten returns at most the first 200 bytes of a reply.
func shorten(body []byte) string {
	if len(body) > 200 {
		body = body[:200]
	}
	return string(body)
}

// callTool calls a tool with tools/call and returns the text of its reply
// and whether the tool failed, which it reports by setting isError. The
// server answers a JSON-RPC error with HTTP status 200, so the function
// checks the reply for an error member as well as the HTTP status.
func callTool(client *http.Client, name string, arguments map[string]any) (string, bool, error) {
	payload, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
		"params": map[string]any{"name": name, "arguments": arguments},
	})
	if err != nil {
		return "", false, err
	}
	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
	if err != nil {
		return "", false, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")

	response, err := client.Do(request)
	if err != nil {
		return "", false, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", false, err
	}
	if response.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
	}
	var reply struct {
		Result *struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
			IsError bool `json:"isError"`
		} `json:"result"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
		return "", false, fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
	}
	if reply.Error != nil {
		return "", false, fmt.Errorf("%s failed: %s", name, reply.Error.Message)
	}
	if len(reply.Result.Content) == 0 {
		return "", false, fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
	}
	return reply.Result.Content[0].Text, reply.Result.IsError, nil
}

// --8<-- [end:config]

// --8<-- [start:select]
// selectCheapProducts runs a SELECT with query_database, and prints the
// column names and each row. The reply repeats the query, with the LIMIT
// that the server adds, and then has a line such as "Results (3 rows):", a
// header line, and one line for each row, with the values separated by
// tabs. The server writes a tab or a newline inside a value as \t or \n,
// and a NULL as an empty string.
func selectCheapProducts(client *http.Client) error {
	text, failed, err := callTool(client, "query_database", map[string]any{
		"query": "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
	})
	if err != nil {
		return err
	}
	if failed {
		return fmt.Errorf("query_database failed: %s", text)
	}
	lines := strings.Split(text, "\n")
	start := -1
	for i, line := range lines {
		if strings.HasPrefix(line, "Results ") {
			start = i
			break
		}
	}
	if start < 0 || start+1 >= len(lines) {
		return fmt.Errorf("unexpected reply: %s", shorten([]byte(text)))
	}
	fmt.Printf("Columns: %s\n", strings.ReplaceAll(lines[start+1], "\t", ", "))
	for _, line := range lines[start+2:] {
		if line != "" {
			fmt.Printf("Row: %s\n", strings.ReplaceAll(line, "\t", ", "))
		}
	}
	return nil
}

// --8<-- [end:select]

// --8<-- [start:insert]
// tryInsert tries to add a row. query_database runs every query in a
// read-only transaction, so PostgreSQL itself refuses the INSERT with
// SQLSTATE 25006, and the tool returns the error with isError set to true.
// The INSERT leaves out id, which the table requires, so that even a server
// that allows writes would refuse it rather than save a row. That is why
// the function checks for the read-only error itself rather than for any
// error, and fails if the write succeeds or fails for another reason. It
// prints only the last line of the error, which holds PostgreSQL's
// message, because some errors start with the query.
func tryInsert(client *http.Client) error {
	text, failed, err := callTool(client, "query_database", map[string]any{
		"query": "INSERT INTO cookbook_mcp.products " +
			"(name, category, price, in_stock, description) " +
			"VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
			"'A made-up product that is never saved')",
	})
	if err != nil {
		return err
	}
	lines := strings.Split(strings.TrimSpace(text), "\n")
	errorLine := lines[len(lines)-1]
	if !failed {
		return errors.New("the server accepted a write")
	}
	if !strings.Contains(text, "SQLSTATE 25006") {
		return fmt.Errorf("the INSERT failed for another reason: %s", errorLine)
	}
	fmt.Printf("INSERT rejected: %s\n", errorLine)
	return nil
}

// --8<-- [end:insert]

// --8<-- [start:main]
// run makes the two calls and returns any error to the caller.
func run() error {
	if token == "" {
		return errors.New("MCP_TOKEN must be set")
	}
	client := &http.Client{Timeout: timeout}
	if err := selectCheapProducts(client); err != nil {
		return err
	}
	return tryInsert(client)
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "MCP Server error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
