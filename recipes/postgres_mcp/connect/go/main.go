// Ellie's Postgres Cookbook
// Connecting to the pgEdge Postgres MCP Server, using net/http.
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

// post sends a JSON-RPC message to the MCP endpoint with a token, and
// returns the HTTP status and the body of the reply.
func post(client *http.Client, withToken string, message any) (int, []byte, error) {
	payload, err := json.Marshal(message)
	if err != nil {
		return 0, nil, err
	}
	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
	if err != nil {
		return 0, nil, err
	}
	request.Header.Set("Authorization", "Bearer "+withToken)
	request.Header.Set("Content-Type", "application/json")

	response, err := client.Do(request)
	if err != nil {
		return 0, nil, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return response.StatusCode, body, err
}

// rpc sends a JSON-RPC request and decodes its result into out. The
// server answers a JSON-RPC error with HTTP status 200, so the function
// checks the reply for an error member as well as the HTTP status.
func rpc(client *http.Client, method string, params any, out any) error {
	status, body, err := post(client, token, map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
	})
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("%s failed with HTTP %d: %s", method, status, shorten(body))
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

// --8<-- [start:health]
// checkHealth checks that the server is running. The /health endpoint
// needs no token.
func checkHealth(client *http.Client) error {
	response, err := client.Get(baseURL + "/health")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("health check failed with HTTP %d: %s", response.StatusCode, shorten(body))
	}
	var health struct {
		Status string `json:"status"`
	}
	if err := json.Unmarshal(body, &health); err != nil || health.Status != "ok" {
		return fmt.Errorf("unexpected response: %s", shorten(body))
	}
	fmt.Println("Health: ok")
	return nil
}

// --8<-- [end:health]

// --8<-- [start:initialize]
// initialize introduces the client to the server, and prints the server's
// name and version and the protocol revision that the server chose. The
// server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and
// answers a revision it does not know with one that it does, so the client
// checks the answer. The notifications/initialized message then completes
// the handshake; it is a notification, with no id, so the server replies
// with HTTP 202 and no body.
func initialize(client *http.Client) error {
	var result struct {
		ProtocolVersion string `json:"protocolVersion"`
		ServerInfo      *struct {
			Name    string `json:"name"`
			Version string `json:"version"`
		} `json:"serverInfo"`
	}
	err := rpc(client, "initialize", map[string]any{
		"protocolVersion": "2025-06-18",
		"capabilities":    map[string]any{},
		"clientInfo":      map[string]string{"name": "cookbook", "version": "1.0.0"},
	}, &result)
	if err != nil {
		return err
	}
	if result.ServerInfo == nil {
		return errors.New("initialize failed: the result has no serverInfo")
	}
	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
	if result.ProtocolVersion != "2025-06-18" {
		return fmt.Errorf("the server chose protocol version %s", result.ProtocolVersion)
	}
	fmt.Printf("Protocol version: %s\n", result.ProtocolVersion)

	status, body, err := post(client, token, map[string]any{
		"jsonrpc": "2.0", "method": "notifications/initialized",
	})
	if err != nil {
		return err
	}
	if status != http.StatusAccepted {
		return fmt.Errorf("notifications/initialized failed with HTTP %d: %s", status, shorten(body))
	}
	return nil
}

// --8<-- [end:initialize]

// --8<-- [start:wrong_token]
// wrongToken sends a request with a token that the server does not know,
// and prints the HTTP status and the server's message, which is a JSON
// object with an error member rather than a JSON-RPC reply.
func wrongToken(client *http.Client) error {
	status, body, err := post(client, "not-a-real-token", map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": map[string]any{},
	})
	if err != nil {
		return err
	}
	if status != http.StatusUnauthorized {
		return fmt.Errorf("expected HTTP 401 for a wrong token, but got %d", status)
	}
	var reply struct {
		Error string `json:"error"`
	}
	message := "no message"
	if json.Unmarshal(body, &reply) == nil && reply.Error != "" {
		message = reply.Error
	}
	fmt.Printf("Wrong token: HTTP %d, %s\n", status, message)
	return nil
}

// --8<-- [end:wrong_token]

// --8<-- [start:main]
// run makes the three checks and returns any error to the caller.
func run() error {
	if token == "" {
		return errors.New("MCP_TOKEN must be set")
	}
	client := &http.Client{Timeout: timeout}
	if err := checkHealth(client); err != nil {
		return err
	}
	if err := initialize(client); err != nil {
		return err
	}
	return wrongToken(client)
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
