// Ellie's Postgres Cookbook
// Reading resources and prompts from the pgEdge Postgres MCP Server, using
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
	"strconv"
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

// rpc sends a JSON-RPC request and decodes its result into out. The
// server answers a JSON-RPC error with HTTP status 200, so the function
// checks the reply for an error member as well as the HTTP status.
func rpc(client *http.Client, method string, params any, out any) error {
	payload, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
	})
	if err != nil {
		return err
	}
	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")

	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("%s failed with HTTP %d: %s", method, response.StatusCode, shorten(body))
	}
	var reply struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
		return fmt.Errorf("%s failed: unexpected response: %s", method, shorten(body))
	}
	if reply.Error != nil {
		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
	}
	if err := json.Unmarshal(reply.Result, out); err != nil {
		return fmt.Errorf("%s failed: unexpected result: %s", method, shorten(reply.Result))
	}
	return nil
}

// --8<-- [end:config]

// --8<-- [start:resources]
// readSystemInfo lists the resources that the server offers, and then
// reads pg://system_info, which describes the PostgreSQL server. The
// contents of a resource are text, which for this one holds a JSON object,
// so the function parses the text a second time. version_number is a
// string such as "180006", from which integer division by 10000 gives the
// major version.
func readSystemInfo(client *http.Client) error {
	var list struct {
		Resources []struct {
			URI string `json:"uri"`
		} `json:"resources"`
	}
	if err := rpc(client, "resources/list", map[string]any{}, &list); err != nil {
		return err
	}
	uris := make([]string, len(list.Resources))
	for i, resource := range list.Resources {
		uris[i] = resource.URI
	}
	fmt.Printf("Resources: %s\n", strings.Join(uris, ", "))

	var result struct {
		Contents []struct {
			Text string `json:"text"`
		} `json:"contents"`
	}
	if err := rpc(client, "resources/read", map[string]any{"uri": "pg://system_info"}, &result); err != nil {
		return err
	}
	if len(result.Contents) == 0 {
		return errors.New("resources/read failed: the result has no contents")
	}
	var info struct {
		VersionNumber string `json:"version_number"`
		AllowWrites   bool   `json:"allow_writes"`
	}
	if err := json.Unmarshal([]byte(result.Contents[0].Text), &info); err != nil {
		return fmt.Errorf("unexpected result: %s", shorten([]byte(result.Contents[0].Text)))
	}
	versionNumber, err := strconv.Atoi(info.VersionNumber)
	if err != nil {
		return fmt.Errorf("unexpected version number: %q", info.VersionNumber)
	}
	fmt.Printf("PostgreSQL major version: %d\n", versionNumber/10000)
	fmt.Printf("Writes allowed: %t\n", info.AllowWrites)
	return nil
}

// --8<-- [end:resources]

// --8<-- [start:prompts]
// readPrompts lists the prompts that the server offers, and then fetches
// explore-database, which takes no arguments. A prompt is a set of
// messages, ready to hand to a language model, that guide it through a
// task with the server's tools.
func readPrompts(client *http.Client) error {
	var list struct {
		Prompts []struct {
			Name string `json:"name"`
		} `json:"prompts"`
	}
	if err := rpc(client, "prompts/list", map[string]any{}, &list); err != nil {
		return err
	}
	names := make([]string, len(list.Prompts))
	for i, prompt := range list.Prompts {
		names[i] = prompt.Name
	}
	fmt.Printf("Prompts: %s\n", strings.Join(names, ", "))

	var prompt struct {
		Description string `json:"description"`
		Messages    []struct {
			Role string `json:"role"`
		} `json:"messages"`
	}
	err := rpc(client, "prompts/get",
		map[string]any{"name": "explore-database", "arguments": map[string]any{}}, &prompt)
	if err != nil {
		return err
	}
	if len(prompt.Messages) == 0 {
		return errors.New("prompts/get failed: the prompt has no messages")
	}
	fmt.Printf("explore-database: %s\n", prompt.Description)
	fmt.Printf("First message role: %s\n", prompt.Messages[0].Role)
	return nil
}

// --8<-- [end:prompts]

// --8<-- [start:main]
// run makes the requests and returns any error to the caller.
func run() error {
	if token == "" {
		return errors.New("MCP_TOKEN must be set")
	}
	client := &http.Client{Timeout: timeout}
	if err := readSystemInfo(client); err != nil {
		return err
	}
	return readPrompts(client)
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
