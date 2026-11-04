// Ellie's Postgres Cookbook
// Listing the regions, sizes, and PostgreSQL versions that the pgEdge
// Starfleet Managed API offers, using the net/http package.
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
// apiGet sends an authenticated GET request to the Managed API and
// decodes the JSON reply into result.
func apiGet(ctx context.Context, token, path string, result any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		baseURL()+"/managed/v1"+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("GET %s failed: %w", path, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("GET %s failed: %s %s", path, resp.Status, detail)
	}
	return json.NewDecoder(resp.Body).Decode(result)
}

// --8<-- [end:api]

// --8<-- [start:regions]
// listRegions returns the identifiers of the regions that can host a
// database.
func listRegions(ctx context.Context, token string) ([]string, error) {
	var regions []struct {
		Region string `json:"region"`
	}
	if err := apiGet(ctx, token, "/regions", &regions); err != nil {
		return nil, err
	}

	names := make([]string, 0, len(regions))
	for _, r := range regions {
		names = append(names, r.Region)
	}
	return names, nil
}

// --8<-- [end:regions]

// --8<-- [start:sizes]
// listSizes returns a description of each size, smallest first.
func listSizes(ctx context.Context, token string) ([]string, error) {
	// A pointer field is nil when the API omits it, which is how a size
	// with no configured price appears.
	var sizes []struct {
		Name        string `json:"name"`
		Connections int    `json:"connections"`
		StorageSize string `json:"storage_size"`
		Pricing     *struct {
			PriceAmount     int64  `json:"price_amount"`
			Currency        string `json:"currency"`
			BillingInterval string `json:"billing_interval"`
		} `json:"pricing"`
	}
	// The pricing option asks the API to include each size's price, which
	// takes a little longer because the API looks it up from billing.
	if err := apiGet(ctx, token, "/sizes?include=pricing", &sizes); err != nil {
		return nil, err
	}

	lines := make([]string, 0, len(sizes))
	for _, s := range sizes {
		line := fmt.Sprintf("%s: %d connections, %s storage", s.Name, s.Connections, s.StorageSize)
		// The amount is in the smallest unit of the currency, such as cents.
		if s.Pricing != nil {
			line += fmt.Sprintf(", %.2f %s per %s",
				float64(s.Pricing.PriceAmount)/100, s.Pricing.Currency, s.Pricing.BillingInterval)
		}
		lines = append(lines, line)
	}
	return lines, nil
}

// --8<-- [end:sizes]

// --8<-- [start:versions]
// listVersions returns the PostgreSQL major versions, newest first,
// marking the one that a new database gets by default.
func listVersions(ctx context.Context, token string) ([]string, error) {
	var versions []struct {
		Version string `json:"version"`
		Default bool   `json:"default"`
	}
	if err := apiGet(ctx, token, "/pg-versions", &versions); err != nil {
		return nil, err
	}

	lines := make([]string, 0, len(versions))
	for _, v := range versions {
		if v.Default {
			lines = append(lines, v.Version+" (default)")
		} else {
			lines = append(lines, v.Version)
		}
	}
	return lines, nil
}

// --8<-- [end:versions]

// --8<-- [start:main]
// printList prints a heading followed by an indented line per item.
func printList(heading string, items []string) {
	fmt.Println(heading)
	for _, item := range items {
		fmt.Printf("  %s\n", item)
	}
}

// run fetches and prints each list, returning any error to the caller.
func run(ctx context.Context) error {
	token, err := getToken(ctx)
	if err != nil {
		return err
	}

	regions, err := listRegions(ctx, token)
	if err != nil {
		return err
	}
	printList("Regions:", regions)

	sizes, err := listSizes(ctx, token)
	if err != nil {
		return err
	}
	printList("Sizes (smallest first):", sizes)

	versions, err := listVersions(ctx, token)
	if err != nil {
		return err
	}
	printList("PostgreSQL versions:", versions)
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
