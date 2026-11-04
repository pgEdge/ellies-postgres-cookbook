/*
 * Ellie's Postgres Cookbook
 * Scheduling a maintenance blackout with the AI DBA Workbench API, using
 * net/http.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

package main

// --8<-- [start:imports]
import (
	"bytes"
	"context"
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

// --8<-- [start:request]
// client gives every request a timeout; the default client has none.
var client = &http.Client{Timeout: 30 * time.Second}

// blackout is the part of a blackout that the program needs.
type blackout struct {
	ID       int64 `json:"id"`
	IsActive bool  `json:"is_active"`
}

// api sends a request to the API and decodes the JSON reply into out, if
// given. A request that the server rejects returns an error that includes
// the message from the server. Cancelling ctx, which the program does when it
// receives SIGINT or SIGTERM, abandons the request.
func api(ctx context.Context, s settings, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequestWithContext(ctx, method, s.baseURL+"/api/v1"+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		text, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("%s %s failed with status %d: %s",
			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// --8<-- [end:request]

// --8<-- [start:create]
// createBlackout creates a blackout for one monitored server and returns
// it. The blackout starts a minute ago, so that a small difference between
// the clocks of this machine and the server cannot leave it inactive, and
// it ends in one hour. The times are in RFC 3339 format.
//
// A signal cannot interrupt this request, because the program would not
// know the ID of a blackout that the server created after the interruption.
func createBlackout(s settings) (blackout, error) {
	now := time.Now().UTC()
	var b blackout
	err := api(context.Background(), s, "POST", "/blackouts", map[string]any{
		"scope":         "server",
		"connection_id": s.connectionID,
		"reason":        "Cookbook maintenance window",
		"start_time":    now.Add(-time.Minute).Format(time.RFC3339),
		"end_time":      now.Add(time.Hour).Format(time.RFC3339),
	}, &b)
	return b, err
}

// --8<-- [end:create]

// --8<-- [start:read]
// getBlackout returns the blackout with the given ID.
func getBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
	var b blackout
	err := api(ctx, s, "GET", fmt.Sprintf("/blackouts/%d", id), nil, &b)
	return b, err
}

// --8<-- [end:read]

// --8<-- [start:stop]
// stopBlackout stops a blackout that is in progress, which sets its end
// time to now, and returns the stopped blackout.
func stopBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
	var b blackout
	err := api(ctx, s, "POST", fmt.Sprintf("/blackouts/%d/stop", id), nil, &b)
	return b, err
}

// --8<-- [end:stop]

// --8<-- [start:delete]
// deleteBlackout deletes a blackout by its ID. A signal cannot interrupt this
// request, because it is the cleanup.
func deleteBlackout(s settings, id int64) error {
	return api(context.Background(), s, "DELETE", fmt.Sprintf("/blackouts/%d", id), nil, nil)
}

// --8<-- [end:delete]

// --8<-- [start:main]
// run does the work. It returns the cleanup that the caller must run if the
// program has created a blackout and not yet deleted it.
func run(ctx context.Context, s settings) (cleanup func() error, err error) {
	created, err := createBlackout(s)
	if err != nil {
		return nil, err
	}
	// Return the cleanup before any later step can fail, so that a failed
	// run does not leave alerts suppressed.
	cleanup = func() error { return deleteBlackout(s, created.ID) }
	fmt.Printf("Created a blackout for the server (active: %t)\n", created.IsActive)

	current, err := getBlackout(ctx, s, created.ID)
	if err != nil {
		return cleanup, err
	}
	fmt.Printf("Read the blackout back (active: %t)\n", current.IsActive)

	stopped, err := stopBlackout(ctx, s, created.ID)
	if err != nil {
		return cleanup, err
	}
	fmt.Printf("Stopped the blackout (active: %t)\n", stopped.IsActive)
	if stopped.IsActive {
		return cleanup, errors.New("the blackout is still active")
	}

	// Report a failed delete here and clear the cleanup, so that main does not
	// try again and print a second error.
	if err := cleanup(); err != nil {
		return nil, fmt.Errorf("could not delete the blackout: %w", err)
	}
	fmt.Println("Deleted the blackout")
	return nil, nil
}

func main() {
	s, err := loadSettings()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	// The handler replaces the default action for these signals, which would
	// end the program before it could delete the blackout. It cancels ctx,
	// which abandons the request in progress, and a second signal does
	// nothing more.
	ctx, stop := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)

	failed := false
	cleanup, err := run(ctx, s)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		failed = true
	}
	if cleanup != nil {
		if err := cleanup(); err != nil {
			fmt.Fprintln(os.Stderr, "Error: could not delete the blackout:", err)
			failed = true
		}
	}
	stop()
	if failed {
		os.Exit(1)
	}
}

// --8<-- [end:main]
