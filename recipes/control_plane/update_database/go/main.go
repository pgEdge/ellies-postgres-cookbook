// Ellie's Postgres Cookbook
// Changing a Postgres setting of a pgEdge Control Plane database, checking
// it from a connection, and putting the original settings back, using
// net/http and pgx.
//
// These examples are for the Control Plane v0.11.0.
//
// The program restores the original settings on every path: after a
// success, after a failure, and after Ctrl-C.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
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

// The password has no default; the Control Plane never returns it, so it
// comes from whoever created the database user.
var (
	baseURL          = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
	databaseID       = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
	databaseUser     = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook")
	databasePassword = os.Getenv("CONTROL_PLANE_DATABASE_PASSWORD")
)

const timeout = 30 * time.Second

// The setting to change, and its new value.
const (
	setting = "work_mem"
	value   = "16MB"
)

// How long to wait for an update to finish, and how often to check.
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

// dbError marks an error from the database connection or its query.
type dbError struct{ err error }

func (e *dbError) Error() string { return e.err.Error() }

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

// --8<-- [start:update]
// spec is kept as plain JSON, so that the update sends back every field
// that the server returned, including any that this program does not
// know about.
type spec = map[string]any

// updateDatabase sends a whole database spec as an update, and returns
// the ID of the task that applies it. The Control Plane compares the spec
// with the current one and changes only what differs; the work happens in
// the task after the reply.
func updateDatabase(ctx context.Context, s spec) (string, error) {
	var reply struct {
		Task struct {
			TaskID string `json:"task_id"`
		} `json:"task"`
	}
	err := call(ctx, http.MethodPost, "/v1/databases/"+databaseID, map[string]any{"spec": s}, &reply)
	return reply.Task.TaskID, err
}

// changedSpec returns a copy of the spec with the setting changed.
// postgresql_conf holds the Postgres settings that the Control Plane
// manages, and may be missing.
func changedSpec(s spec) spec {
	conf := map[string]any{}
	if current, ok := s["postgresql_conf"].(map[string]any); ok {
		maps.Copy(conf, current)
	}
	conf[setting] = value
	changed := maps.Clone(s)
	changed["postgresql_conf"] = conf
	return changed
}

// --8<-- [end:update]

// --8<-- [start:wait]
// waitForTask polls a task until it finishes, and returns an error unless
// it completed.
func waitForTask(ctx context.Context, taskID string) error {
	deadline := time.Now().Add(waitFor)
	for time.Now().Before(deadline) {
		var task struct {
			Status string `json:"status"`
		}
		if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID+"/tasks/"+taskID, nil, &task); err != nil {
			return err
		}
		switch task.Status {
		case "completed":
			return nil
		case "failed", "canceled":
			return fmt.Errorf("the task finished with the status %s", task.Status)
		}
		if err := sleep(ctx); err != nil {
			return err
		}
	}
	return fmt.Errorf("the task was still running after %d seconds", int(waitFor.Seconds()))
}

// --8<-- [end:wait]

// --8<-- [start:connect]
// showSetting connects to the first available instance and returns the
// current value of the setting. Each instance runs one node, and its
// connection_info holds the address and port that clients use.
func showSetting(ctx context.Context) (string, error) {
	var database struct {
		Spec struct {
			DatabaseName string `json:"database_name"`
		} `json:"spec"`
		Instances []struct {
			State          string `json:"state"`
			ConnectionInfo struct {
				Addresses []string `json:"addresses"`
				Port      int      `json:"port"`
			} `json:"connection_info"`
		} `json:"instances"`
	}
	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
		return "", err
	}
	host, port := "", 0
	for _, i := range database.Instances {
		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
			host, port = i.ConnectionInfo.Addresses[0], i.ConnectionInfo.Port
			break
		}
	}
	if host == "" {
		return "", fmt.Errorf("no available instance of %s", databaseID)
	}

	// net/url takes care of escaping any special characters in the user
	// name, password, or database name.
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(databaseUser, databasePassword),
		Host:     net.JoinHostPort(host, strconv.Itoa(port)),
		Path:     "/" + database.Spec.DatabaseName,
		RawQuery: "connect_timeout=30",
	}
	conn, err := pgx.Connect(ctx, u.String())
	if err != nil {
		return "", &dbError{err}
	}
	// Close the connection when the function returns, whether or not the
	// query failed.
	defer conn.Close(ctx)

	var current string
	if err := conn.QueryRow(ctx, "SELECT current_setting($1)", setting).Scan(&current); err != nil {
		return "", &dbError{err}
	}
	return current, nil
}

// --8<-- [end:connect]

// --8<-- [start:restore]
// restore sends the original spec back and waits for the task. The
// Control Plane answers 409 whilst another task, such as the update, is
// still running on the database, so the program repeats the request, as
// it does when no reply arrived or the server failed. The cleanup runs
// after Ctrl-C, so it uses a context that never ends.
func restore(original spec) error {
	ctx := context.Background()
	deadline := time.Now().Add(waitFor)
	for {
		taskID, err := updateDatabase(ctx, original)
		if err == nil {
			return waitForTask(ctx, taskID)
		}
		status := statusOf(err)
		transient := status == 0 || status == 409 || status >= 500
		if !transient || time.Now().After(deadline) {
			return err
		}
		sleep(ctx)
	}
}

// --8<-- [end:restore]

// --8<-- [start:main]
// run changes the setting and checks it, and returns any error to the
// caller. It fills in original, and sets changed once the settings may
// have changed, so that the caller knows whether to restore them.
func run(ctx context.Context, original *spec, changed *bool) error {
	// The spec that the API returns leaves out the passwords of the
	// database users, and an update may leave them out too, which keeps
	// them unchanged.
	var database struct {
		Spec spec `json:"spec"`
	}
	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
		return err
	}
	*original = database.Spec

	// Restore unless the server refused the request with a 4xx status,
	// which means that it changed nothing.
	fmt.Printf("Setting %s to %s\n", setting, value)
	*changed = true
	taskID, err := updateDatabase(ctx, changedSpec(*original))
	if err != nil {
		if status := statusOf(err); status >= 400 && status < 500 {
			*changed = false
		}
		return err
	}
	if err := waitForTask(ctx, taskID); err != nil {
		return err
	}
	fmt.Println("Update completed")

	current, err := showSetting(ctx)
	if err != nil {
		return err
	}
	fmt.Printf("%s is now %s\n", setting, current)
	return nil
}

// main restores the original settings whether the example succeeded,
// failed, or was interrupted, and exits with a non-zero status after a
// failure.
func main() {
	if databasePassword == "" {
		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
		os.Exit(1)
	}

	// Ctrl-C and SIGTERM end the context instead of the process, which
	// lets the program restore the settings before it exits. The handlers
	// stay in place, so a further Ctrl-C does not end the process during
	// the cleanup either.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)

	exitCode := 0
	changed := false
	var original spec
	if err := run(ctx, &original, &changed); err != nil {
		var dbErr *dbError
		switch {
		case ctx.Err() != nil:
			fmt.Fprintln(os.Stderr, "Interrupted")
			exitCode = 130
		case errors.As(err, &dbErr):
			fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
			exitCode = 1
		default:
			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
			exitCode = 1
		}
	}

	if changed {
		if err := restore(original); err != nil {
			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
			fmt.Fprintf(os.Stderr, "Restore the settings of the database %s by hand\n", databaseID)
			exitCode = 1
		} else {
			fmt.Println("Restored the original settings")
		}
	}
	// os.Exit skips deferred calls, so release the signal handlers here.
	stop()
	os.Exit(exitCode)
}

// --8<-- [end:main]
