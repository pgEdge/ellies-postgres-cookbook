/*
 * Ellie's Postgres Cookbook
 * Registering a server to monitor with the AI DBA Workbench API, using
 * net/http.
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
	"strings"
	"time"
)

// --8<-- [end:imports]

// --8<-- [start:config]
const serverName = "cookbook-register-server"

// settings holds the values that the program reads from the environment.
type settings struct {
	baseURL        string
	username       string
	password       string
	connectionID   string
	serverPassword string
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
		username:     os.Getenv("WORKBENCH_USERNAME"),
		password:     os.Getenv("WORKBENCH_PASSWORD"),
		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
		// The Workbench refuses to register a server without a password,
		// even one that uses trust authentication, so fall back to a
		// placeholder.
		serverPassword: envOr("PGPASSWORD", "unused-with-trust-authentication"),
	}
	if s.username == "" || s.password == "" || s.connectionID == "" {
		return s, errors.New("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID must be set")
	}
	return s, nil
}

// --8<-- [end:config]

// --8<-- [start:request]
// client gives every request a timeout; the default client has none.
var client = &http.Client{Timeout: 30 * time.Second}

// api sends a request to the API and returns the response, which the caller
// must close. A request that the server rejects returns an error that
// includes the message from the server.
func api(method, baseURL, path, token string, body any) (*http.Response, error) {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequest(method, baseURL+"/api/v1"+path, reader)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		defer resp.Body.Close()
		text, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("%s %s failed with status %d: %s",
			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
	}
	return resp, nil
}

// apiJSON sends a request and decodes the JSON reply into out, if given.
func apiJSON(method, baseURL, path, token string, body, out any) error {
	resp, err := api(method, baseURL, path, token, body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// --8<-- [end:request]

// --8<-- [start:login]
// login logs in and returns the session token. The server returns the token
// in a session_token cookie, not in the body of the reply.
func login(baseURL, username, password string) (string, error) {
	resp, err := api("POST", baseURL, "/auth/login", "", map[string]string{
		"username": username,
		"password": password,
	})
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	for _, cookie := range resp.Cookies() {
		if cookie.Name == "session_token" {
			return cookie.Value, nil
		}
	}
	return "", errors.New("the login reply had no session_token cookie")
}

// --8<-- [end:login]

// --8<-- [start:lookup]
// connection is the part of a connection that the program needs.
type connection struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Host         string `json:"host"`
	Port         int    `json:"port"`
	DatabaseName string `json:"database_name"`
	Username     string `json:"username"`
	SSLMode      string `json:"ssl_mode"`
	IsMonitored  bool   `json:"is_monitored"`
}

// getConnection returns the details of an existing connection, which the
// program uses as the address of the server to register.
func getConnection(baseURL, session, id string) (connection, error) {
	var c connection
	err := apiJSON("GET", baseURL, "/connections/"+id, session, nil, &c)
	return c, err
}

// --8<-- [end:lookup]

// --8<-- [start:register]
// registerServer registers a server and returns the ID of the new
// connection. The address comes from an existing connection. The request
// must include a password, and a description, which the server needs in
// version 1.0.0.
func registerServer(baseURL, session, name string, template connection, password string) (int64, error) {
	var created connection
	err := apiJSON("POST", baseURL, "/connections", session, map[string]any{
		"name":          name,
		"description":   "Registered by the cookbook",
		"host":          template.Host,
		"port":          template.Port,
		"database_name": template.DatabaseName,
		"username":      template.Username,
		"ssl_mode":      template.SSLMode,
		"password":      password,
		"is_monitored":  true,
		"is_shared":     false,
	}, &created)
	return created.ID, err
}

// --8<-- [end:register]

// --8<-- [start:list]
// findConnection returns the named connection from the list, or nil if the
// list has no such connection.
func findConnection(baseURL, session, name string) (*connection, error) {
	var connections []connection
	if err := apiJSON("GET", baseURL, "/connections", session, nil, &connections); err != nil {
		return nil, err
	}
	for i := range connections {
		if connections[i].Name == name {
			return &connections[i], nil
		}
	}
	return nil, nil
}

// --8<-- [end:list]

// --8<-- [start:delete]
// deleteConnection deletes a connection by its ID.
func deleteConnection(baseURL, session string, id int64) error {
	return apiJSON("DELETE", baseURL, fmt.Sprintf("/connections/%d", id),
		session, nil, nil)
}

// --8<-- [end:delete]

// --8<-- [start:main]
// run does the work. It returns the cleanup that the caller must run if the
// program has registered a server and not yet deleted it.
func run(s settings) (cleanup func() error, err error) {
	session, err := login(s.baseURL, s.username, s.password)
	if err != nil {
		return nil, err
	}
	template, err := getConnection(s.baseURL, session, s.connectionID)
	if err != nil {
		return nil, err
	}

	newID, err := registerServer(s.baseURL, session, serverName, template, s.serverPassword)
	if err != nil {
		return nil, err
	}
	// Return the cleanup before any later step can fail, so that a failed
	// run does not leave a server registered.
	cleanup = func() error { return deleteConnection(s.baseURL, session, newID) }
	fmt.Printf("Registered the server '%s'\n", serverName)

	found, err := findConnection(s.baseURL, session, serverName)
	if err != nil {
		return cleanup, err
	}
	if found == nil {
		return cleanup, errors.New("the new connection is missing from the list")
	}
	fmt.Printf("Found '%s' in the list (monitored: %t)\n", serverName, found.IsMonitored)

	if err := cleanup(); err != nil {
		return cleanup, err
	}
	cleanup = nil
	fmt.Println("Deleted the connection")

	found, err = findConnection(s.baseURL, session, serverName)
	if err != nil {
		return nil, err
	}
	if found != nil {
		return nil, errors.New("the connection is still in the list")
	}
	fmt.Println("The connection is no longer in the list")
	return nil, nil
}

func main() {
	s, err := loadSettings()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	failed := false
	cleanup, err := run(s)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		failed = true
	}
	if cleanup != nil {
		if err := cleanup(); err != nil {
			fmt.Fprintln(os.Stderr, "Error: could not delete the connection:", err)
			failed = true
		}
	}
	if failed {
		os.Exit(1)
	}
}

// --8<-- [end:main]
