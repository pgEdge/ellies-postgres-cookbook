// Ellie's Postgres Cookbook
// Connecting to PostgreSQL and running a scalar query, using pgx.
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

func run(ctx context.Context) error {
	// --8<-- [start:connect]
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	// --8<-- [end:connect]
	// --8<-- [start:cleanup]
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)
	// --8<-- [end:cleanup]

	// --8<-- [start:query]
	// Always pass values as parameters rather than building them into the
	// SQL string; pgx sends them separately, which prevents SQL injection.
	var count int64
	err = conn.QueryRow(ctx,
		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
		"int4",
	).Scan(&count)
	if err != nil {
		return fmt.Errorf("query failed: %w", err)
	}

	fmt.Printf("Number of types named 'int4': %d\n", count)
	// --8<-- [end:query]

	return nil
}

// --8<-- [start:errors]
// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:errors]
