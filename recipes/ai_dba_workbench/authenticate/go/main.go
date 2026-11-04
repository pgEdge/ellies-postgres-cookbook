/*
 * Ellie's Postgres Cookbook
 * Authenticating with the AI DBA Workbench API, using net/http.
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
// settings holds the values that the program reads from the environment.
type settings struct {
	baseURL  string
	username string
	password string
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
		baseURL:  strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
		username: os.Getenv("WORKBENCH_USERNAME"),
		password: os.Getenv("WORKBENCH_PASSWORD"),
	}
	if s.username == "" || s.password == "" {
		return s, errors.New("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set")
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

// --8<-- [start:user_info]
// userInfo returns the user that a token belongs to, with its superuser flag.
func userInfo(baseURL, token string) (string, error) {
	var info struct {
		Username    string `json:"username"`
		IsSuperuser bool   `json:"is_superuser"`
	}
	if err := apiJSON("GET", baseURL, "/user/info", token, nil, &info); err != nil {
		return "", err
	}
	return fmt.Sprintf("%s (superuser: %t)", info.Username, info.IsSuperuser), nil
}

// --8<-- [end:user_info]

// --8<-- [start:create_token]
// createdToken is the part of the reply that the program needs.
type createdToken struct {
	ID    int64  `json:"id"`
	Token string `json:"token"`
}

// createToken creates an API token for a user and returns its ID and its
// value. The server shows the value only once. The token expires after an
// hour.
func createToken(baseURL, session, owner, annotation string) (createdToken, error) {
	var created createdToken
	err := apiJSON("POST", baseURL, "/rbac/tokens", session, map[string]string{
		"owner_username": owner,
		"annotation":     annotation,
		"expires_in":     "1h",
	}, &created)
	return created, err
}

// --8<-- [end:create_token]

// --8<-- [start:delete_token]
// deleteToken deletes an API token by its ID.
func deleteToken(baseURL, session string, tokenID int64) error {
	return apiJSON("DELETE", baseURL, fmt.Sprintf("/rbac/tokens/%d", tokenID),
		session, nil, nil)
}

// --8<-- [end:delete_token]

// --8<-- [start:main]
// run does the work and returns the cleanup that the caller must run, if a
// token was created.
func run(s settings) (cleanup func() error, err error) {
	session, err := login(s.baseURL, s.username, s.password)
	if err != nil {
		return nil, err
	}
	fmt.Println("Logged in with a session token")
	who, err := userInfo(s.baseURL, session)
	if err != nil {
		return nil, err
	}
	fmt.Println("Session token belongs to", who)

	created, err := createToken(s.baseURL, session, s.username, "cookbook-authenticate")
	if err != nil {
		return nil, err
	}
	// Return the cleanup before any later step can fail, so that a failed
	// run does not leave a token behind.
	cleanup = func() error { return deleteToken(s.baseURL, session, created.ID) }
	fmt.Println("Created the API token 'cookbook-authenticate'")
	who, err = userInfo(s.baseURL, created.Token)
	if err != nil {
		return cleanup, err
	}
	fmt.Println("API token belongs to", who)
	return cleanup, nil
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
			fmt.Fprintln(os.Stderr, "Error: could not delete the token:", err)
			failed = true
		} else {
			fmt.Println("Deleted the API token")
		}
	}
	if failed {
		os.Exit(1)
	}
}

// --8<-- [end:main]
