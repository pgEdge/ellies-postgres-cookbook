// Ellie's Postgres Cookbook
// Searching by meaning through the pgEdge Postgres MCP Server, using
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
	"regexp"
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

// The server turns the query into an embedding before it searches, which
// can take a while if the embedding model has to load first, so the
// timeout is longer than in the other recipes.
const timeout = 90 * time.Second

const query = "a gift for an amateur astronomer"

// shorten returns at most the first 200 bytes of a reply.
func shorten(body []byte) string {
	if len(body) > 200 {
		body = body[:200]
	}
	return string(body)
}

// callTool calls a tool with tools/call and returns the text of its
// reply. The server answers a JSON-RPC error with HTTP status 200, and a
// tool that fails returns a normal result with isError set, so the
// function checks for both as well as the HTTP status.
func callTool(client *http.Client, name string, arguments map[string]any) (string, error) {
	payload, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
		"params": map[string]any{"name": name, "arguments": arguments},
	})
	if err != nil {
		return "", err
	}
	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")

	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", err
	}
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
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
		return "", fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
	}
	if reply.Error != nil {
		return "", fmt.Errorf("%s failed: %s", name, reply.Error.Message)
	}
	if len(reply.Result.Content) == 0 {
		return "", fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
	}
	text := reply.Result.Content[0].Text
	if reply.Result.IsError {
		return "", fmt.Errorf("%s failed: %s", name, text)
	}
	return text, nil
}

// --8<-- [end:config]

// --8<-- [start:search]
// resultLine matches the line that starts each result, such as
// "Result 1/3".
var resultLine = regexp.MustCompile(`^Result \d+/\d+$`)

// search searches the product descriptions for the query, and prints the
// number of results and the name of the product that matches it most
// closely. similarity_search finds the closest rows by vector distance,
// and then reorders them, mixing in a keyword score and favouring variety,
// so the first result in the reply is not always the closest. Each result
// has a line such as "Source: cookbook_mcp.products.description (vector
// search rank: #1, chunk: 1)"; the function picks the result ranked first
// by the vector search, whose text follows the first blank line after it.
// Every description starts with the product's name and a colon.
func search(client *http.Client) error {
	text, err := callTool(client, "similarity_search", map[string]any{
		"table_name": "cookbook_mcp.products",
		"query_text": query,
		"top_n":      3,
	})
	if err != nil {
		return err
	}
	fmt.Printf("Query: %s\n", query)
	lines := strings.Split(text, "\n")
	count := 0
	for _, line := range lines {
		if resultLine.MatchString(line) {
			count++
		}
	}
	fmt.Printf("Results: %d\n", count)

	source := -1
	for i, line := range lines {
		if strings.HasPrefix(line, "Source: ") &&
			strings.HasSuffix(line, "(vector search rank: #1, chunk: 1)") {
			source = i
			break
		}
	}
	best := ""
	if source >= 0 {
		for i := source + 1; i+1 < len(lines); i++ {
			if lines[i] == "" {
				best = lines[i+1]
				break
			}
		}
	}
	name, _, ok := strings.Cut(best, ": ")
	if !ok {
		return fmt.Errorf("the reply had no closest match: %s", shorten([]byte(text)))
	}
	fmt.Printf("Best match: %s\n", name)
	return nil
}

// --8<-- [end:search]

// --8<-- [start:main]
// run makes the search and returns any error to the caller.
func run() error {
	if token == "" {
		return errors.New("MCP_TOKEN must be set")
	}
	client := &http.Client{Timeout: timeout}
	return search(client)
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
