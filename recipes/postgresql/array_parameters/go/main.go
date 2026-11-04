// Ellie's Postgres Cookbook
// Passing a list of values as a single array parameter, using pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"

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

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String()
}

// --8<-- [end:config]

// --8<-- [start:connect]
// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:query]
// findTypes returns the names from the list that exist as data types.
func findTypes(ctx context.Context, conn *pgx.Conn, names []string) ([]string, error) {
	// The whole list travels as one array parameter, so the SQL text is
	// the same however many values the list holds. pgx converts a Go
	// slice into a PostgreSQL array.
	rows, err := conn.Query(ctx,
		"SELECT typname FROM pg_catalog.pg_type "+
			"WHERE typname = ANY($1) ORDER BY typname",
		names,
	)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}

	// CollectRows reads every row, closes the rows, and reports any error.
	found, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	return found, nil
}

// --8<-- [end:query]

// --8<-- [start:main]
// run connects, runs the query, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	wanted := []string{"int4", "text", "bool", "no_such_type"}

	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	found, err := findTypes(ctx, conn, wanted)
	if err != nil {
		return err
	}

	fmt.Printf("Found %d of %d types: %s\n",
		len(found), len(wanted), strings.Join(found, ", "))
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
