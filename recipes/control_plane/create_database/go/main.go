// Ellie's Postgres Cookbook
// Creating a pgEdge Control Plane database on one host, waiting until it
// is available, and deleting it again, using net/http.
//
// These examples are for the Control Plane v0.11.0.
//
// The database runs in containers on the host until it is deleted, so
// this program deletes the database it creates on every path: after a
// success, after a failure, and after Ctrl-C.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
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

// The new database listens on the given port on its host, so choose one
// that is free.
var (
	baseURL = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
	port    = envOr("CONTROL_PLANE_RECIPE_PORT", "6433")
)

const timeout = 30 * time.Second

// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const (
	waitFor      = 600 * time.Second
	pollInterval = 5 * time.Second
)

// apiError is an error reply from the Control Plane, with its HTTP status.
type apiError struct {
	status int
	body   string
}

func (e *apiError) Error() string {
	return fmt.Sprintf("HTTP %d, %.200s", e.status, e.body)
}

// statusOf returns the HTTP status of an error reply, or 0 if no reply
// arrived.
func statusOf(err error) int {
	var apiErr *apiError
	if errors.As(err, &apiErr) {
		return apiErr.status
	}
	return 0
}

var client = &http.Client{Timeout: timeout}

// call sends a request to the server, and decodes the reply into out if
// out is not nil. The context stops the request when the user presses
// Ctrl-C.
func call(ctx context.Context, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(ctx, method, baseURL+path, reader)
	if err != nil {
		return err
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}

	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	reply, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}

	// Go treats an error status as a normal response, so check it here.
	if response.StatusCode >= 400 {
		return &apiError{response.StatusCode, strings.TrimSpace(string(reply))}
	}
	if out != nil {
		if err := json.Unmarshal(reply, out); err != nil {
			return fmt.Errorf("unexpected response: %.200s", reply)
		}
	}
	return nil
}

// sleep waits for the poll interval, or until the context ends.
func sleep(ctx context.Context) error {
	select {
	case <-time.After(pollInterval):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// --8<-- [end:config]

// --8<-- [start:host]
// firstHost returns the ID of the first host in the cluster. A database
// places each of its nodes on one or more hosts, which run the Postgres
// containers.
func firstHost(ctx context.Context) (string, error) {
	var reply struct {
		Hosts []struct {
			ID string `json:"id"`
		} `json:"hosts"`
	}
	if err := call(ctx, http.MethodGet, "/v1/hosts", nil, &reply); err != nil {
		return "", err
	}
	if len(reply.Hosts) == 0 {
		return "", errors.New("the cluster has no hosts")
	}
	return reply.Hosts[0].ID, nil
}

// --8<-- [end:host]

// --8<-- [start:create]
// createDatabase asks the Control Plane to create a database with one
// node. The reply holds the database and the task that creates it; the
// work happens in the background after the reply.
func createDatabase(ctx context.Context, databaseID, host string) error {
	portNumber, err := strconv.Atoi(port)
	if err != nil {
		return fmt.Errorf("CONTROL_PLANE_RECIPE_PORT is not a number: %s", port)
	}
	body := map[string]any{
		"id": databaseID,
		"spec": map[string]any{
			"database_name": "recipe",
			"port":          portNumber,
			"nodes": []map[string]any{
				{"name": "n1", "host_ids": []string{host}},
			},
		},
	}
	return call(ctx, http.MethodPost, "/v1/databases", body, nil)
}

// --8<-- [end:create]

// --8<-- [start:wait]
// waitUntilAvailable polls the database, printing its state each time it
// changes, until the state is available, and returns the port of its
// first instance. Each instance runs one node, and its connection_info
// holds the address and port that clients use. A failed state ends the
// wait at once.
func waitUntilAvailable(ctx context.Context, databaseID string) (int, error) {
	deadline := time.Now().Add(waitFor)
	last := ""
	for time.Now().Before(deadline) {
		var database struct {
			State     string `json:"state"`
			Instances []struct {
				ConnectionInfo struct {
					Port int `json:"port"`
				} `json:"connection_info"`
			} `json:"instances"`
		}
		err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database)
		if err != nil {
			return 0, err
		}
		if database.State != last {
			fmt.Printf("Database state: %s\n", database.State)
			last = database.State
		}
		switch {
		case database.State == "available" && len(database.Instances) > 0:
			return database.Instances[0].ConnectionInfo.Port, nil
		case database.State == "failed":
			return 0, errors.New("the database has the state failed")
		}
		if err := sleep(ctx); err != nil {
			return 0, err
		}
	}
	return 0, fmt.Errorf("the database was not available after %v", waitFor)
}

// --8<-- [end:wait]

// --8<-- [start:delete]
// isTransient reports whether a failed request is worth repeating: no
// reply arrived, the server failed, or it answered 409, which the Control
// Plane does whilst another task, such as the create, is still running on
// the database.
func isTransient(err error) bool {
	status := statusOf(err)
	return status == 0 || status == http.StatusConflict || status >= 500
}

// deleteDatabase deletes the database and waits until the API no longer
// has it. A 404 means that the database is already gone. The cleanup runs
// after Ctrl-C, so it uses a context that never ends.
func deleteDatabase(databaseID string) error {
	ctx := context.Background()
	path := "/v1/databases/" + databaseID
	deadline := time.Now().Add(waitFor)
	for {
		err := call(ctx, http.MethodDelete, path, nil, nil)
		if err == nil {
			break
		}
		if statusOf(err) == http.StatusNotFound {
			return nil
		}
		if !isTransient(err) || time.Now().After(deadline) {
			return err
		}
		time.Sleep(pollInterval)
	}

	// The delete starts a task that removes the database; a 404 shows that
	// it has finished.
	for time.Now().Before(deadline) {
		err := call(ctx, http.MethodGet, path, nil, nil)
		if statusOf(err) == http.StatusNotFound {
			return nil
		}
		if err != nil && !isTransient(err) {
			return err
		}
		time.Sleep(pollInterval)
	}
	return fmt.Errorf("the database was still present after %v", waitFor)
}

// --8<-- [end:delete]

// --8<-- [start:main]
// run creates the database and waits for it, and returns any error to the
// caller. It sets created once the database may exist, so that the caller
// knows whether to delete it.
func run(ctx context.Context, databaseID string, created *bool) error {
	host, err := firstHost(ctx)
	if err != nil {
		return err
	}
	fmt.Printf("Host: %s\n", host)

	// Clean up unless the server refused the request with a 4xx status,
	// which means it created nothing; a 409, for example, means that a
	// database with this ID already exists, and is not this program's to
	// delete.
	*created = true
	if err := createDatabase(ctx, databaseID, host); err != nil {
		if status := statusOf(err); status >= 400 && status < 500 {
			*created = false
		}
		return err
	}
	fmt.Printf("Created database %s\n", databaseID)

	instancePort, err := waitUntilAvailable(ctx, databaseID)
	if err != nil {
		return err
	}
	fmt.Printf("Database is available on port %d\n", instancePort)
	return nil
}

// main deletes the database whether the example succeeded, failed, or was
// interrupted, and exits with a non-zero status after a failure.
func main() {
	// Ctrl-C and SIGTERM end the context instead of the process, which
	// lets the program delete its database before it exits. The handlers
	// stay in place, so a further Ctrl-C does not end the process during
	// the cleanup either.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)

	// The client chooses the ID of a new database, so the program knows it
	// before the request, and can delete the database even if the reply
	// never arrives. The random suffix keeps the ID unique.
	suffix := make([]byte, 3)
	rand.Read(suffix)
	databaseID := "cookbook-recipe-" + hex.EncodeToString(suffix)

	exitCode := 0
	created := false
	if err := run(ctx, databaseID, &created); err != nil {
		if ctx.Err() != nil {
			fmt.Fprintln(os.Stderr, "Interrupted")
			exitCode = 130
		} else {
			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
			exitCode = 1
		}
	}

	if created {
		if err := deleteDatabase(databaseID); err != nil {
			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
			fmt.Fprintf(os.Stderr, "Delete the database %s by hand\n", databaseID)
			exitCode = 1
		} else {
			fmt.Println("Deleted database")
		}
	}
	// os.Exit skips deferred calls, so release the signal handlers here.
	stop()
	os.Exit(exitCode)
}

// --8<-- [end:main]
