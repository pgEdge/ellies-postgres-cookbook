// Ellie's Postgres Cookbook
// Finding the address of a pgEdge Control Plane database and connecting
// to it, using net/http and pgx.
//
// These examples are for the Control Plane v0.11.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
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

// --8<-- [start:find]
// instance holds the settings for connecting to one instance.
type instance struct {
	Node     string
	Host     string
	Port     int
	Database string
}

// findInstance returns the connection settings for the first instance of
// the database that is available. Each instance runs one node of the
// database, and its connection_info holds the addresses and port that
// clients use.
func findInstance(client *http.Client) (*instance, error) {
	var database struct {
		Spec struct {
			DatabaseName string `json:"database_name"`
		} `json:"spec"`
		Instances []struct {
			NodeName       string `json:"node_name"`
			State          string `json:"state"`
			ConnectionInfo struct {
				Addresses []string `json:"addresses"`
				Port      int      `json:"port"`
			} `json:"connection_info"`
		} `json:"instances"`
	}
	if err := get(client, "/v1/databases/"+databaseID, &database); err != nil {
		return nil, err
	}
	for _, i := range database.Instances {
		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
			return &instance{
				Node:     i.NodeName,
				Host:     i.ConnectionInfo.Addresses[0],
				Port:     i.ConnectionInfo.Port,
				Database: database.Spec.DatabaseName,
			}, nil
		}
	}
	return nil, fmt.Errorf("no available instance of %s", databaseID)
}

// --8<-- [end:find]

// --8<-- [start:connect]
// query connects to the instance, and returns the name of the database
// and the version of the Spock extension.
func query(ctx context.Context, i *instance) (database, spock string, err error) {
	// net/url takes care of escaping any special characters in the user
	// name, password, or database name.
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(databaseUser, databasePassword),
		Host:     net.JoinHostPort(i.Host, strconv.Itoa(i.Port)),
		Path:     "/" + i.Database,
		RawQuery: "connect_timeout=30",
	}

	conn, err := pgx.Connect(ctx, u.String())
	if err != nil {
		return "", "", err
	}
	// Close the connection when the function returns, whether or not a
	// query failed.
	defer conn.Close(ctx)

	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
		return "", "", err
	}
	err = conn.QueryRow(ctx,
		"SELECT extversion FROM pg_extension WHERE extname = 'spock'").Scan(&spock)
	if errors.Is(err, pgx.ErrNoRows) {
		return database, "not installed", nil
	}
	return database, spock, err
}

// --8<-- [end:connect]

// --8<-- [start:main]
func main() {
	if databasePassword == "" {
		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
		os.Exit(1)
	}

	i, err := findInstance(&http.Client{Timeout: timeout})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Connecting to node %s\n", i.Node)

	database, spock, err := query(context.Background(), i)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Connected to database %s\n", database)
	fmt.Printf("Spock: %s\n", spock)
}

// --8<-- [end:main]
