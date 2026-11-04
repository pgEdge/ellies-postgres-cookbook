// Ellie's Postgres Cookbook
// Reading a large result in batches, using pgx.
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

// --8<-- [start:read_batches]
// readRows reads every row of a large result, and returns the number of
// rows and the sum of their values.
func readRows(ctx context.Context, conn *pgx.Conn) (rowsRead, total int64, err error) {
	// Query does not load the result into memory. pgx reads rows from the
	// network as the loop asks for them, so the program holds one row at
	// a time; pgx has no batch size to set, because the connection's
	// buffer takes the place of the batch.
	rows, err := conn.Query(ctx, "SELECT g FROM generate_series(1, 100000) AS g")
	if err != nil {
		return 0, 0, fmt.Errorf("query failed: %w", err)
	}
	// Close releases the connection for further use, even if the loop
	// stops early.
	defer rows.Close()

	for rows.Next() {
		var value int32
		if err := rows.Scan(&value); err != nil {
			return 0, 0, fmt.Errorf("scan failed: %w", err)
		}
		rowsRead++
		total += int64(value)
	}

	// Next returns false at the end of the result and after an error, so
	// the program checks Err to tell the two apart.
	if err := rows.Err(); err != nil {
		return 0, 0, fmt.Errorf("read failed: %w", err)
	}
	return rowsRead, total, nil
}

// --8<-- [end:read_batches]

// --8<-- [start:main]
// run connects, reads the rows, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	rowsRead, total, err := readRows(ctx, conn)
	if err != nil {
		return err
	}

	fmt.Printf("Rows read: %d\n", rowsRead)
	fmt.Printf("Sum of values: %d\n", total)
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
