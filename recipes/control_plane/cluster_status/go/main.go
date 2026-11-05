// Ellie's Postgres Cookbook
// Checking the version of the pgEdge Control Plane, its cluster, and the
// state of each host, using net/http.
//
// These examples are for the Control Plane v0.11.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
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

var baseURL = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")

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

// --8<-- [start:version]
// showVersion prints the version of the Control Plane server.
func showVersion(client *http.Client) error {
	var body struct {
		Version *string `json:"version"`
	}
	if err := get(client, "/v1/version", &body); err != nil {
		return err
	}
	if body.Version == nil {
		return errors.New("unexpected response: missing version")
	}
	fmt.Printf("Version: %s\n", *body.Version)
	return nil
}

// --8<-- [end:version]

// --8<-- [start:cluster]
// showCluster prints the state of the cluster. A server answers this
// request only once its cluster has been initialised, and it then reports
// "available"; the health of the cluster shows in the state of each host.
func showCluster(client *http.Client) error {
	var body struct {
		Status struct {
			State *string `json:"state"`
		} `json:"status"`
	}
	if err := get(client, "/v1/cluster", &body); err != nil {
		return err
	}
	if body.Status.State == nil {
		return errors.New("unexpected response: missing state")
	}
	fmt.Printf("Cluster: %s\n", *body.Status.State)
	return nil
}

// --8<-- [end:cluster]

// --8<-- [start:hosts]
// showHosts lists the hosts in the cluster with their states, and returns
// whether every host is "healthy". The other states are "degraded",
// "unreachable" and "unknown".
func showHosts(client *http.Client) (bool, error) {
	var body struct {
		Hosts *[]struct {
			ID     string `json:"id"`
			Status struct {
				State string `json:"state"`
			} `json:"status"`
		} `json:"hosts"`
	}
	if err := get(client, "/v1/hosts", &body); err != nil {
		return false, err
	}
	if body.Hosts == nil {
		return false, errors.New("unexpected response: missing hosts")
	}

	fmt.Printf("Hosts (%d):\n", len(*body.Hosts))
	healthy := true
	for _, host := range *body.Hosts {
		state := host.Status.State
		if state == "" {
			state = "unknown"
		}
		fmt.Printf("- %s: %s\n", host.ID, state)
		healthy = healthy && state == "healthy"
	}
	return healthy, nil
}

// --8<-- [end:hosts]

// --8<-- [start:main]
// run performs the checks and returns any error to the caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	if err := showVersion(client); err != nil {
		return err
	}
	if err := showCluster(client); err != nil {
		return err
	}
	healthy, err := showHosts(client)
	if err != nil {
		return err
	}

	// Report an unhealthy host with the exit status.
	if !healthy {
		return errors.New("a host is not healthy")
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
