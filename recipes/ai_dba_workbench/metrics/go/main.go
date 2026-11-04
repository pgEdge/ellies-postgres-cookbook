/*
 * Ellie's Postgres Cookbook
 * Querying metrics and top queries with the AI DBA Workbench API, using
 * net/http.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

package main

// --8<-- [start:imports]
import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
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
	connectionID string
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
		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
		token:        os.Getenv("WORKBENCH_TOKEN"),
		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
	}
	if s.token == "" || s.connectionID == "" {
		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
	}
	return s, nil
}

// --8<-- [end:config]

// --8<-- [start:request]
// client gives every request a timeout; the default client has none.
var client = &http.Client{Timeout: 30 * time.Second}

// get sends a GET request to the API and decodes the JSON reply into out. A
// request that the server rejects returns an error that includes the
// message from the server.
func get(s settings, path string, params url.Values, out any) error {
	req, err := http.NewRequest("GET", s.baseURL+"/api/v1"+path+"?"+params.Encode(), nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.token)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		text, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("GET %s failed with status %d: %s",
			path, resp.StatusCode, strings.TrimSpace(string(text)))
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// --8<-- [end:request]

// --8<-- [start:query_metrics]
// series is one metric, with its points over time.
type series struct {
	Name string `json:"name"`
	Data []struct {
		Time  string  `json:"time"`
		Value float64 `json:"value"`
	} `json:"data"`
}

// queryMetrics prints one line for each series that the pg_stat_database
// probe collected over the last hour, in six buckets: the metric, the number
// of points, and the latest value.
func queryMetrics(s settings) error {
	var result []series
	err := get(s, "/metrics/query", url.Values{
		"connection_id": {s.connectionID},
		"probe_name":    {"pg_stat_database"},
		"time_range":    {"1h"},
		"buckets":       {"6"},
		"metrics":       {"numbackends,xact_commit"},
	}, &result)
	if err != nil {
		return err
	}
	for _, m := range result {
		if len(m.Data) == 0 {
			fmt.Printf("%s: no data\n", m.Name)
			continue
		}
		latest := m.Data[len(m.Data)-1].Value
		fmt.Printf("%s: %d points, latest %s\n", m.Name, len(m.Data),
			strconv.FormatFloat(latest, 'f', -1, 64))
	}
	return nil
}

// --8<-- [end:query_metrics]

// --8<-- [start:top_queries]
// topQuery is the part of a top query that the program prints.
type topQuery struct {
	Query        string  `json:"query"`
	Calls        int64   `json:"calls"`
	MeanExecTime float64 `json:"mean_exec_time"`
}

// topQueries prints the queries that have used the most execution time, as
// the pg_stat_statements extension on the monitored server recorded them.
// The query text is cut to 50 characters on one line.
func topQueries(s settings) error {
	var queries []topQuery
	err := get(s, "/metrics/top-queries", url.Values{
		"connection_id":     {s.connectionID},
		"limit":             {"5"},
		"order_by":          {"total_exec_time"},
		"exclude_collector": {"true"},
	}, &queries)
	if err != nil {
		return err
	}
	if len(queries) == 0 {
		fmt.Println("No statements recorded (is pg_stat_statements installed?)")
		return nil
	}

	fmt.Println("Top queries by total execution time:")
	for i, q := range queries {
		text := []rune(strings.Join(strings.Fields(q.Query), " "))
		if len(text) > 50 {
			text = text[:50]
		}
		mean := math.Round(q.MeanExecTime*100) / 100
		fmt.Printf("%d. %d calls, %s ms mean: %s\n", i+1, q.Calls,
			strconv.FormatFloat(mean, 'f', -1, 64), string(text))
	}
	return nil
}

// --8<-- [end:top_queries]

// --8<-- [start:main]
func main() {
	s, err := loadSettings()
	if err == nil {
		err = queryMetrics(s)
	}
	if err == nil {
		err = topQueries(s)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
