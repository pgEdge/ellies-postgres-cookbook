// Ellie's Postgres Cookbook
// Storing and searching vectors with pgvector, using pgx.
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

// --8<-- [start:schema]
// createSchema enables pgvector and creates a temporary table of colours.
func createSchema(ctx context.Context, conn *pgx.Conn) error {
	// vector(3) fixes the number of dimensions, one for each of the red,
	// green, and blue components. The temporary table disappears when the
	// session ends, so the program can run repeatedly. An HNSW index
	// speeds up nearest-neighbour searches; vector_l2_ops matches the <->
	// (Euclidean distance) operator used by the search.
	statements := []string{
		"CREATE EXTENSION IF NOT EXISTS vector",
		"CREATE TEMPORARY TABLE colours (" +
			"name text PRIMARY KEY, rgb vector(3) NOT NULL)",
		"CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
	}
	for _, statement := range statements {
		if _, err := conn.Exec(ctx, statement); err != nil {
			return fmt.Errorf("schema setup failed: %w", err)
		}
	}
	return nil
}

// --8<-- [end:schema]

// --8<-- [start:insert]
// insertColours stores five colours, each as a vector of its RGB
// components.
func insertColours(ctx context.Context, conn *pgx.Conn) error {
	colours := [][2]string{
		{"red", "[1,0,0]"},
		{"green", "[0,1,0]"},
		{"blue", "[0,0,1]"},
		{"yellow", "[1,1,0]"},
		{"white", "[1,1,1]"},
	}
	for _, colour := range colours {
		// A vector travels as text in pgvector's [x,y,z] format, and the
		// ::vector cast converts it on the server, so the driver needs no
		// vector-specific support.
		_, err := conn.Exec(ctx,
			"INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
			colour[0], colour[1])
		if err != nil {
			return fmt.Errorf("insert failed: %w", err)
		}
	}
	return nil
}

// --8<-- [end:insert]

// --8<-- [start:search]
// nearestColours returns the names of the colours nearest to the target
// vector.
func nearestColours(ctx context.Context, conn *pgx.Conn, target string, count int) ([]string, error) {
	// <-> is the Euclidean (L2) distance operator, so ordering by it puts
	// the nearest colour first.
	rows, err := conn.Query(ctx,
		"SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
		target, count)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}

	// CollectRows reads every row, and closes the result when it is done.
	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	return names, nil
}

// --8<-- [end:search]

// --8<-- [start:main]
// run connects, stores the colours, searches them, and prints the result,
// returning any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	if err := createSchema(ctx, conn); err != nil {
		return err
	}
	if err := insertColours(ctx, conn); err != nil {
		return err
	}

	target := "[0.9,0.7,0.2]"
	names, err := nearestColours(ctx, conn, target, 3)
	if err != nil {
		return err
	}

	fmt.Printf("Colours nearest to %s:\n", target)
	for i, name := range names {
		fmt.Printf("%d. %s\n", i+1, name)
	}
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
