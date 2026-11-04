/*
 * Ellie's Postgres Cookbook
 * Calling AI DBA Workbench MCP tools, using net/http.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

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
	"strconv"
	"strings"
	"time"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// settings holds the values that the program reads from the environment.
type settings struct {
	baseURL      string
	token        string
	connectionID int
}

// envOr returns the value of an environment variable, or the fallback if
// the variable is unset or empty, as an unset variable would be.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// loadSettings reads the settings from the environment.
func loadSettings() (settings, error) {
	s := settings{
		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
		token:   os.Getenv("WORKBENCH_TOKEN"),
	}
	id := os.Getenv("WORKBENCH_CONNECTION_ID")
	if s.token == "" || id == "" {
		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
	}
	var err error
	if s.connectionID, err = strconv.Atoi(id); err != nil {
		return s, fmt.Errorf("WORKBENCH_CONNECTION_ID must be a number: %w", err)
	}
	return s, nil
}

// --8<-- [end:config]

// --8<-- [start:rpc]
// client gives every request a timeout; the default client has none.
var client = &http.Client{Timeout: 30 * time.Second}

// rpc sends a JSON-RPC request to the MCP endpoint and decodes the result
// into out. The server answers a JSON-RPC error with HTTP status 200, so the
// function checks the reply for an error member as well as for an HTTP
// failure.
func rpc(s settings, method string, params, out any) error {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequest("POST", s.baseURL+"/mcp/v1", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		text, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("%s failed with status %d: %s",
			method, resp.StatusCode, strings.TrimSpace(string(text)))
	}

	var reply struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&reply); err != nil {
		return err
	}
	if reply.Error != nil {
		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
	}
	return json.Unmarshal(reply.Result, out)
}

// --8<-- [end:rpc]

// --8<-- [start:initialize]
// initialize introduces the client to the server and prints the server's
// name and version. The Workbench keeps no session, so a client can skip
// this step.
func initialize(s settings) error {
	var result struct {
		ServerInfo struct {
			Name    string `json:"name"`
			Version string `json:"version"`
		} `json:"serverInfo"`
	}
	err := rpc(s, "initialize", map[string]any{
		"protocolVersion": "2024-11-05",
		"capabilities":    map[string]any{},
		"clientInfo":      map[string]any{"name": "cookbook", "version": "1.0.0"},
	}, &result)
	if err != nil {
		return err
	}
	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
	return nil
}

// --8<-- [end:initialize]

// --8<-- [start:list_tools]
// listTools lists the tools, checks that the two that the program calls are
// present, and prints the arguments that each one requires.
func listTools(s settings) error {
	var result struct {
		Tools []struct {
			Name        string `json:"name"`
			InputSchema struct {
				Required []string `json:"required"`
			} `json:"inputSchema"`
		} `json:"tools"`
	}
	if err := rpc(s, "tools/list", map[string]any{}, &result); err != nil {
		return err
	}
	// The server lists its tools in no fixed order, so look the two tools up
	// by name.
	for _, name := range []string{"query_database", "execute_explain"} {
		found := false
		for _, tool := range result.Tools {
			if tool.Name == name {
				fmt.Printf("%s requires: %s\n", name, strings.Join(tool.InputSchema.Required, ", "))
				found = true
			}
		}
		if !found {
			return fmt.Errorf("the server does not offer %s", name)
		}
	}
	return nil
}

// --8<-- [end:list_tools]

// --8<-- [start:call_tool]
// callTool calls a tool and returns the text of its reply. A tool that fails
// returns a normal result with isError set, so the function checks that flag
// too.
func callTool(s settings, name string, arguments map[string]any) (string, error) {
	var result struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
		IsError bool `json:"isError"`
	}
	err := rpc(s, "tools/call", map[string]any{"name": name, "arguments": arguments}, &result)
	if err != nil {
		return "", err
	}
	if len(result.Content) == 0 {
		return "", fmt.Errorf("%s returned no content", name)
	}
	text := result.Content[0].Text
	if result.IsError {
		return "", fmt.Errorf("%s failed: %s", name, text)
	}
	return text, nil
}

// --8<-- [end:call_tool]

// --8<-- [start:query_database]
// queryDatabase runs a harmless read-only query with query_database and
// prints the column names and the rows. The reply is text that starts with
// the connection and the query, and then has a "Results" line followed by
// the rows in tab-separated form, so the function prints only what follows
// that line.
func queryDatabase(s settings) error {
	text, err := callTool(s, "query_database", map[string]any{
		"connection_id": s.connectionID,
		"query":         "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
	})
	if err != nil {
		return err
	}
	_, results, found := strings.Cut(text, "\nResults")
	if !found {
		return errors.New("the reply had no results")
	}
	// Skip the rest of the Results line, then turn the tabs into commas.
	number := 0
	for _, line := range strings.Split(results, "\n")[1:] {
		if line == "" {
			continue
		}
		label := "Row"
		if number == 0 {
			label = "Columns"
		}
		fmt.Printf("%s: %s\n", label, strings.Join(strings.Split(line, "\t"), ", "))
		number++
	}
	return nil
}

// --8<-- [end:query_database]

// --8<-- [start:execute_explain]
// planStart finds the first word of the plan, which follows a line of equals
// signs.
var planStart = regexp.MustCompile(`Execution Plan:\n=+\n(\S+)`)

// executeExplain plans a query with execute_explain, without running it, and
// prints the type of the first node of the plan. Setting analyze to true
// would run the query.
func executeExplain(s settings) error {
	text, err := callTool(s, "execute_explain", map[string]any{
		"connection_id": s.connectionID,
		"query":         "SELECT 1 + 1",
		"analyze":       false,
	})
	if err != nil {
		return err
	}
	match := planStart.FindStringSubmatch(text)
	if match == nil {
		return errors.New("the reply had no execution plan")
	}
	fmt.Printf("Plan starts with: %s\n", match[1])
	return nil
}

// --8<-- [end:execute_explain]

// --8<-- [start:main]
func run() error {
	s, err := loadSettings()
	if err != nil {
		return err
	}
	for _, step := range []func(settings) error{
		initialize, listTools, queryDatabase, executeExplain,
	} {
		if err := step(s); err != nil {
			return err
		}
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
