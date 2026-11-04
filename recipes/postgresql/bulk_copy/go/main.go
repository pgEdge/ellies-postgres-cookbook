// Ellie's Postgres Cookbook
// Loading rows in bulk with COPY, using pgx.
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

// --8<-- [start:create_table]
// createTable creates a temporary table, which only this session can see
// and which PostgreSQL drops when the session ends.
func createTable(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx,
		"CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
	if err != nil {
		return fmt.Errorf("create table failed: %w", err)
	}
	return nil
}

// --8<-- [end:create_table]

// --8<-- [start:generate_rows]
// generateRows returns a source that pgx asks for one row at a time, so
// the program never builds the whole list of rows. Each row holds the
// values for the id and name columns.
func generateRows(count int) pgx.CopyFromSource {
	return pgx.CopyFromSlice(count, func(i int) ([]any, error) {
		id := i + 1
		return []any{id, fmt.Sprintf("item %d", id)}, nil
	})
}

// --8<-- [end:generate_rows]

// --8<-- [start:copy_rows]
// copyRows loads the rows with COPY ... FROM STDIN and returns how many
// rows the server stored.
func copyRows(ctx context.Context, conn *pgx.Conn, rows pgx.CopyFromSource) (int64, error) {
	// CopyFrom uses the binary COPY format, which sends each value in its
	// native form, so there are no tabs, newlines, or backslashes to
	// escape. It is much faster than one INSERT for each row.
	copied, err := conn.CopyFrom(ctx,
		pgx.Identifier{"items"},
		[]string{"id", "name"},
		rows,
	)
	if err != nil {
		return 0, fmt.Errorf("copy failed: %w", err)
	}
	return copied, nil
}

// --8<-- [end:copy_rows]

// --8<-- [start:summarise]
// summarise returns the number of rows in the table and the sum of their
// ids.
func summarise(ctx context.Context, conn *pgx.Conn) (count, total int64, err error) {
	// sum() of an int returns a bigint, which scans into an int64.
	err = conn.QueryRow(ctx, "SELECT count(*), sum(id) FROM items").
		Scan(&count, &total)
	if err != nil {
		return 0, 0, fmt.Errorf("query failed: %w", err)
	}
	return count, total, nil
}

// --8<-- [end:summarise]

// --8<-- [start:main]
// run connects, loads the rows, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	if err := createTable(ctx, conn); err != nil {
		return err
	}

	copied, err := copyRows(ctx, conn, generateRows(1000))
	if err != nil {
		return err
	}
	fmt.Printf("Copied %d rows\n", copied)

	count, total, err := summarise(ctx, conn)
	if err != nil {
		return err
	}
	fmt.Printf("Rows in table: %d\n", count)
	fmt.Printf("Sum of ids: %d\n", total)
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
