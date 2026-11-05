// Ellie's Postgres Cookbook
// Finding the task that created a pgEdge Control Plane database, and
// following its log until the task finishes, using net/http.
//
// These examples are for the Control Plane v0.11.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"encoding/json"
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
	baseURL    = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
	databaseID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
)

const timeout = 30 * time.Second

// How long to follow a task that is still running, and how often to check.
const (
	followFor    = 600 * time.Second
	pollInterval = 5 * time.Second
)

// finalStatuses holds the statuses after which a task does not change
// again.
var finalStatuses = map[string]bool{"completed": true, "failed": true, "canceled": true}

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

// --8<-- [start:list]
// task holds the fields of a task that this program uses.
type task struct {
	TaskID string `json:"task_id"`
	Type   string `json:"type"`
	Status string `json:"status"`
}

// findCreateTask returns the ID of the task that created the database.
// Every create, update and delete runs as a task. The IDs sort by
// creation time, and sort_order=asc lists the oldest task first.
func findCreateTask(client *http.Client) (string, error) {
	var reply struct {
		Tasks []task `json:"tasks"`
	}
	err := get(client, "/v1/databases/"+databaseID+"/tasks?sort_order=asc", &reply)
	if err != nil {
		return "", err
	}
	for _, t := range reply.Tasks {
		if t.Type == "create" {
			return t.TaskID, nil
		}
	}
	return "", fmt.Errorf("no create task for %s", databaseID)
}

// --8<-- [end:list]

// --8<-- [start:follow]
// followTask prints the log of a task as it grows, until the task
// finishes, and returns its final status. Each log reply carries
// last_entry_id, and passing that back as after_entry_id fetches only the
// newer entries. The status is read before the log, so that once it is
// final, the log that follows it is complete.
func followTask(client *http.Client, taskID string) (string, error) {
	path := "/v1/databases/" + databaseID + "/tasks/" + taskID
	deadline := time.Now().Add(followFor)
	after := ""
	for {
		var t task
		if err := get(client, path, &t); err != nil {
			return "", err
		}

		var log struct {
			LastEntryID string `json:"last_entry_id"`
			Entries     []struct {
				Message string `json:"message"`
			} `json:"entries"`
		}
		query := ""
		if after != "" {
			query = "?after_entry_id=" + url.QueryEscape(after)
		}
		if err := get(client, path+"/log"+query, &log); err != nil {
			return "", err
		}
		for _, entry := range log.Entries {
			fmt.Printf("Log: %s\n", entry.Message)
		}
		if log.LastEntryID != "" {
			after = log.LastEntryID
		}

		if finalStatuses[t.Status] {
			return t.Status, nil
		}
		if time.Now().After(deadline) {
			return "", fmt.Errorf("task %s was still %s after %v", taskID, t.Status, followFor)
		}
		time.Sleep(pollInterval)
	}
}

// --8<-- [end:follow]

// --8<-- [start:main]
// run finds the task and follows it, and returns any error to the
// caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	taskID, err := findCreateTask(client)
	if err != nil {
		return err
	}
	fmt.Println("Task: create")
	status, err := followTask(client, taskID)
	if err != nil {
		return err
	}
	fmt.Printf("Status: %s\n", status)
	if status != "completed" {
		return fmt.Errorf("the task finished with the status %s", status)
	}
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
