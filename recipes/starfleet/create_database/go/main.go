// Ellie's Postgres Cookbook
// Creating a pgEdge Starfleet database, waiting until it is available,
// and deleting it again, using the net/http package.
//
// The Starfleet service bills for every database from the moment that it
// becomes connectable, so this program deletes the database it creates on
// every path: after a success, after a failure, and after Ctrl-C.
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
	"strings"
	"syscall"
	"time"
)

// --8<-- [end:imports]

// --8<-- [start:config]
const (
	// How long to wait for a database to become available, or to
	// disappear after a delete, and how often to check.
	timeout      = 15 * time.Minute
	pollInterval = 10 * time.Second
)

// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// baseURL is the root of the Starfleet API, without a trailing slash.
func baseURL() string {
	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
}

// httpClient gives every request a timeout; the default client has none.
var httpClient = &http.Client{Timeout: 30 * time.Second}

// --8<-- [end:config]

// --8<-- [start:token]
// getToken exchanges the client ID and secret for an access token, which
// the Managed API accepts as a bearer token until it expires.
func getToken(ctx context.Context) (string, error) {
	clientID := os.Getenv("STARFLEET_CLIENT_ID")
	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
	if clientID == "" || clientSecret == "" {
		return "", errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
	}

	body, err := json.Marshal(map[string]string{
		"grant_type":    "client_credentials",
		"client_id":     clientID,
		"client_secret": clientSecret,
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()

	// A non-2xx status is not a Go error, so check it explicitly.
	if resp.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return "", fmt.Errorf("token request failed: %s %s", resp.Status, detail)
	}

	var token struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
		return "", fmt.Errorf("decoding the token response: %w", err)
	}
	return token.AccessToken, nil
}

// --8<-- [end:token]

// --8<-- [start:api]
// APIError is an error reply from the Managed API, with its HTTP status.
type APIError struct {
	Status  int
	Message string
}

func (e *APIError) Error() string { return e.Message }

// api sends an authenticated request to the Managed API. It encodes body
// as JSON if it is not nil, and decodes the reply into result if that is
// not nil and the reply has content.
func api(ctx context.Context, token, method, path string, body, result any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequestWithContext(ctx, method, baseURL()+"/managed/v1"+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s failed: %w", method, path, err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		return &APIError{
			Status:  resp.StatusCode,
			Message: fmt.Sprintf("%s %s failed: %s %s", method, path, resp.Status, data),
		}
	}
	if result == nil || len(data) == 0 {
		return nil
	}
	return json.Unmarshal(data, result)
}

// sleep waits for the interval, or until the context ends.
func sleep(ctx context.Context) error {
	select {
	case <-time.After(pollInterval):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// --8<-- [end:api]

// --8<-- [start:placement]
// choosePlacement returns the region and size for the new database. The
// API lists sizes smallest first, so the first one is the cheapest. The
// API does not price regions, so the example takes the first one.
func choosePlacement(ctx context.Context, token string) (region, size string, err error) {
	var regions []struct {
		Region string `json:"region"`
	}
	var sizes []struct {
		Name string `json:"name"`
	}
	if err = api(ctx, token, http.MethodGet, "/regions", nil, &regions); err != nil {
		return
	}
	if err = api(ctx, token, http.MethodGet, "/sizes", nil, &sizes); err != nil {
		return
	}
	if len(regions) == 0 || len(sizes) == 0 {
		err = errors.New("the API offers no region or size")
		return
	}
	return regions[0].Region, sizes[0].Name, nil
}

// --8<-- [end:placement]

// --8<-- [start:create]
// Database is the part of the API's description of a database that the
// example uses.
type Database struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
	Status      string `json:"status"`
}

// randomSuffix returns six random hexadecimal digits.
func randomSuffix() (string, error) {
	raw := make([]byte, 3)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw), nil
}

// createDatabase creates a database that only this machine can reach,
// and returns the API's description of it, which includes its ID.
func createDatabase(ctx context.Context, token, name, displayName, region, size string) (*Database, error) {
	// A new database is closed to everyone until an allowlist rule admits
	// an address. The API reports the address it sees this request come
	// from, which is the one to admit; a bare address means a single host.
	var ip struct {
		IPAddress string `json:"ip_address"`
	}
	if err := api(ctx, token, http.MethodGet, "/client-ip", nil, &ip); err != nil {
		return nil, err
	}

	var database Database
	err := api(ctx, token, http.MethodPost, "/databases", map[string]any{
		// The name becomes the Postgres database name, so it holds only
		// letters and digits, and the readable cookbook- prefix goes in
		// the display name. The program also uses the name to find the
		// database again if the reply to this request is lost.
		"name":         name,
		"display_name": displayName,
		"region":       region,
		"size":         size,
		"ip_allowlist": map[string]any{
			"rules": []map[string]string{{"cidr": ip.IPAddress, "label": "cookbook"}},
		},
	}, &database)
	if err != nil {
		return nil, err
	}
	return &database, nil
}

// --8<-- [end:create]

// --8<-- [start:wait]
// waitUntilAvailable polls the database until its status is available.
func waitUntilAvailable(ctx context.Context, token, id string) error {
	deadline := time.Now().Add(timeout)
	last := ""
	for time.Now().Before(deadline) {
		var database Database
		if err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, &database); err != nil {
			return err
		}
		if database.Status != last {
			fmt.Printf("Database status: %s\n", database.Status)
			last = database.Status
		}
		if database.Status == "available" {
			return nil
		}
		// The API does not document its status values; the example
		// treats these two as failures, which end the wait at once
		// instead of leaving it to run until the time limit.
		if database.Status == "degraded" || database.Status == "failed" {
			return fmt.Errorf("the database has the status %s", database.Status)
		}
		if err := sleep(ctx); err != nil {
			return err
		}
	}
	return fmt.Errorf("the database was not available after %s", timeout)
}

// --8<-- [end:wait]

// --8<-- [start:delete]
// isStatus reports whether err is an API error with the given status.
func isStatus(err error, status int) bool {
	var apiErr *APIError
	return errors.As(err, &apiErr) && apiErr.Status == status
}

// isTransient reports whether a failed request is worth repeating: no
// reply arrived, the service is overloaded or failing, or it answered 409,
// which the API does whilst a database is still being created.
func isTransient(err error) bool {
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		return true
	}
	return apiErr.Status == http.StatusConflict ||
		apiErr.Status == http.StatusTooManyRequests ||
		apiErr.Status >= 500
}

// findDatabase returns the ID of the database with the given name, or an
// empty string. The program uses it when the reply to the create request
// was lost.
func findDatabase(ctx context.Context, token, name string) (string, error) {
	var databases []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	err := api(ctx, token, http.MethodGet, "/databases?limit=100&descending=true", nil, &databases)
	if err != nil {
		return "", err
	}
	for _, database := range databases {
		if database.Name == name {
			return database.ID, nil
		}
	}
	return "", nil
}

// deleteDatabase deletes the database and waits until the API no longer
// lists it.
func deleteDatabase(ctx context.Context, token, id string) error {
	deadline := time.Now().Add(timeout)
	for {
		err := api(ctx, token, http.MethodDelete, "/databases/"+id, nil, nil)
		if err == nil {
			break
		}
		if isStatus(err, http.StatusNotFound) {
			return nil
		}
		if !isTransient(err) || time.Now().After(deadline) {
			return err
		}
		if err := sleep(ctx); err != nil {
			return err
		}
	}

	// The delete starts the teardown; a 404 shows that it has finished.
	for time.Now().Before(deadline) {
		err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, nil)
		if isStatus(err, http.StatusNotFound) {
			return nil
		}
		if err != nil && !isTransient(err) {
			return err
		}
		if err := sleep(ctx); err != nil {
			return err
		}
	}
	return fmt.Errorf("the database was still present after %s", timeout)
}

// --8<-- [end:delete]

// --8<-- [start:main]
// run creates the database, waits for it, and always deletes it, returning
// any error to the caller.
func run() (err error) {
	// Ctrl-C and SIGTERM cancel ctx instead of ending the process, so the
	// deferred cleanup below still runs.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	token, err := getToken(ctx)
	if err != nil {
		return err
	}

	region, size, err := choosePlacement(ctx, token)
	if err != nil {
		return err
	}
	fmt.Printf("Region: %s\n", region)
	fmt.Printf("Size: %s\n", size)

	// Choose the name before the request, so that the program can find
	// the database even if the reply to the request never arrives.
	suffix, err := randomSuffix()
	if err != nil {
		return err
	}
	name, displayName := "cookbook"+suffix, "cookbook-"+suffix

	// Delete the database whether the example succeeded, failed, or was
	// interrupted, because the service bills for it until then. The
	// cleanup uses its own context, because ctx ends on Ctrl-C, and the
	// signal handler above keeps absorbing any further signals until run
	// returns.
	var databaseID string
	defer func() {
		cleanup := context.Background()
		if databaseID == "" {
			id, findErr := findDatabase(cleanup, token, name)
			if findErr != nil {
				err = errors.Join(err, fmt.Errorf("looking for database %s: %w", name, findErr))
				return
			}
			databaseID = id
		}
		if databaseID == "" {
			return
		}
		if delErr := deleteDatabase(cleanup, token, databaseID); delErr != nil {
			err = errors.Join(err, fmt.Errorf("deleting database %s: %w", databaseID, delErr))
			return
		}
		fmt.Println("Deleted database")
	}()

	database, err := createDatabase(ctx, token, name, displayName, region, size)
	if err != nil {
		return err
	}
	databaseID = database.ID
	fmt.Printf("Created database %s\n", database.DisplayName)

	if err := waitUntilAvailable(ctx, token, database.ID); err != nil {
		return err
	}
	fmt.Println("Database is available")
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
