// Ellie's Postgres Cookbook
// Exchanging a client ID and secret for a pgEdge Starfleet access token,
// using the net/http package.
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
	"net/http"
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

// baseURL is the root of the Starfleet API, without a trailing slash.
func baseURL() string {
	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
}

// httpClient gives every request a timeout; the default client has none.
var httpClient = &http.Client{Timeout: 30 * time.Second}

// --8<-- [end:config]

// --8<-- [start:token]
// AccessToken is the response from the token endpoint.
type AccessToken struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

// getToken exchanges the client ID and secret for an access token. The
// token endpoint belongs to the account API, and accepts the OAuth 2.0
// client credentials grant as a JSON body.
func getToken(ctx context.Context) (*AccessToken, error) {
	clientID := os.Getenv("STARFLEET_CLIENT_ID")
	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
	if clientID == "" || clientSecret == "" {
		return nil, errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
	}

	body, err := json.Marshal(map[string]string{
		"grant_type":    "client_credentials",
		"client_id":     clientID,
		"client_secret": clientSecret,
	})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()

	// A non-2xx status is not a Go error, so check it explicitly.
	if resp.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("token request failed: %s %s", resp.Status, detail)
	}

	var token AccessToken
	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
		return nil, fmt.Errorf("decoding the token response: %w", err)
	}
	return &token, nil
}

// --8<-- [end:token]

// --8<-- [start:main]
// run requests a token and prints its details, returning any error to the
// caller.
func run(ctx context.Context) error {
	token, err := getToken(ctx)
	if err != nil {
		return err
	}

	// Never print the token itself; it grants access to the account.
	fmt.Printf("Token type: %s\n", token.TokenType)
	fmt.Printf("Token length: %d characters\n", len(token.AccessToken))
	fmt.Printf("Expires in: %d seconds\n", token.ExpiresIn)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
