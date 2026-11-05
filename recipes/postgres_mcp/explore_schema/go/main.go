// Ellie's Postgres Cookbook
// Exploring a schema through the pgEdge Postgres MCP Server, using
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

const timeout = 30 * time.Second

// The schema and table that scripts/start_postgres_mcp.sh creates.
const (
	schema = "cookbook_mcp"
	table  = "products"
)

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

// --8<-- [start:parse_tsv]
// parseTsv reads the table in a tool's reply into a list of rows, each a
// map keyed by column name. The reply starts with a line or two about the
// database, and then has a header line and one line for each row, with
// the values separated by tabs. The server writes a tab or a newline
// inside a value as \t or \n, so splitting on them is safe. The header is
// the first line that starts with "schema", the first column of every
// table that get_schema_info returns.
func parseTsv(text string) ([]map[string]string, error) {
	lines := strings.Split(text, "\n")
	start := -1
	for i, line := range lines {
		if strings.HasPrefix(line, "schema\t") {
			start = i
			break
		}
	}
	if start < 0 {
		return nil, fmt.Errorf("the reply had no table: %s", shorten([]byte(text)))
	}
	header := strings.Split(lines[start], "\t")
	var rows []map[string]string
	for _, line := range lines[start+1:] {
		if line == "" {
			continue
		}
		values := strings.Split(line, "\t")
		row := make(map[string]string, len(header))
		for i, name := range header {
			if i < len(values) {
				row[name] = values[i]
			}
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// --8<-- [end:parse_tsv]

// --8<-- [start:list_tables]
// listTables lists the tables in the schema with their comments. With
// compact set to true, get_schema_info returns one line for each table,
// without its columns, which suits a first look at a large database.
func listTables(client *http.Client) error {
	text, err := callTool(client, "get_schema_info",
		map[string]any{"schema_name": schema, "compact": true})
	if err != nil {
		return err
	}
	fmt.Printf("Tables in %s:\n", schema)
	rows, err := parseTsv(text)
	if err != nil {
		return err
	}
	for _, row := range rows {
		comment := row["table_desc"]
		if comment == "" {
			comment = "(no comment)"
		}
		fmt.Printf("- %s: %s\n", row["table"], comment)
	}
	return nil
}

// --8<-- [end:list_tables]

// --8<-- [start:describe_table]
// describeTable lists the columns of one table with their types. Given a
// table_name, get_schema_info returns one line for each column, which also
// carries the table's details.
func describeTable(client *http.Client) error {
	text, err := callTool(client, "get_schema_info",
		map[string]any{"schema_name": schema, "table_name": table})
	if err != nil {
		return err
	}
	rows, err := parseTsv(text)
	if err != nil {
		return err
	}
	if len(rows) == 0 {
		return fmt.Errorf("%s.%s has no columns", schema, table)
	}
	fmt.Printf("Columns of %s.%s:\n", schema, table)
	for _, row := range rows {
		key := ""
		if row["is_pk"] == "true" {
			key = " (primary key)"
		}
		fmt.Printf("- %s: %s%s\n", row["column"], row["data_type"], key)
	}
	return nil
}

// --8<-- [end:describe_table]

// --8<-- [start:count_rows]
// countLine matches the line at the end of a count_rows reply, such as
// "Count: 4".
var countLine = regexp.MustCompile(`(?m)^Count: (\d+)$`)

// countInStock counts the products in stock with count_rows. The where
// argument is a condition without the WHERE keyword; the server rejects
// one that contains a subquery.
func countInStock(client *http.Client) error {
	text, err := callTool(client, "count_rows",
		map[string]any{"schema": schema, "table": table, "where": "in_stock"})
	if err != nil {
		return err
	}
	match := countLine.FindStringSubmatch(text)
	if match == nil {
		return fmt.Errorf("the reply had no count: %s", shorten([]byte(text)))
	}
	fmt.Printf("Products in stock: %s\n", match[1])
	return nil
}

// --8<-- [end:count_rows]

// --8<-- [start:main]
// run makes the three calls and returns any error to the caller.
func run() error {
	if token == "" {
		return errors.New("MCP_TOKEN must be set")
	}
	client := &http.Client{Timeout: timeout}
	if err := listTables(client); err != nil {
		return err
	}
	if err := describeTable(client); err != nil {
		return err
	}
	return countInStock(client)
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
