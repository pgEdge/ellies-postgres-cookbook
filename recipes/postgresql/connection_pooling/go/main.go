// Ellie's Postgres Cookbook
// Using a connection pool, with pgx and pgxpool.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// poolSize is the most connections that the pool opens at any one time.
const poolSize = 2

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

// --8<-- [start:pool]
// createPool creates a pool that holds at most poolSize connections.
func createPool(ctx context.Context) (*pgxpool.Pool, error) {
	config, err := pgxpool.ParseConfig(connString())
	if err != nil {
		return nil, fmt.Errorf("invalid settings: %w", err)
	}
	config.MaxConns = poolSize

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("pool creation failed: %w", err)
	}

	// The pool opens connections on demand, so creating it never fails
	// because of an unreachable server. Ping borrows a connection, which
	// opens the first one and reports any problem straight away.
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return pool, nil
}

// --8<-- [end:pool]

// --8<-- [start:query]
// runQuery borrows a connection from the pool, and returns the number
// back.
func runQuery(ctx context.Context, pool *pgxpool.Pool, number int32) (int32, error) {
	// pool.QueryRow borrows a connection, runs the statement, and returns
	// the connection to the pool once Scan has read the row. Pass values
	// as parameters rather than building them into the SQL string. The
	// cast gives the parameter a type, which the server cannot infer from
	// SELECT $1 alone.
	var result int32
	err := pool.QueryRow(ctx, "SELECT $1::int", number).Scan(&result)
	if err != nil {
		return 0, fmt.Errorf("query failed: %w", err)
	}
	return result, nil
}

// --8<-- [end:query]

// --8<-- [start:main]
// run creates the pool, runs five queries through it at once, and prints
// the sum, returning any error to the caller.
func run(ctx context.Context) error {
	pool, err := createPool(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the pool, and every connection in it, when
	// run() returns, whether or not an error occurred.
	defer pool.Close()

	// Five goroutines ask for a connection at once, but the pool has only
	// two, so the others wait their turn. Each goroutine writes only to
	// its own element of the slices, so no further locking is needed.
	const queries = 5
	results := make([]int32, queries)
	errs := make([]error, queries)
	var wg sync.WaitGroup
	for i := range queries {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i], errs[i] = runQuery(ctx, pool, int32(i+1))
		}()
	}
	wg.Wait()

	if err := errors.Join(errs...); err != nil {
		return err
	}

	var sum int32
	for _, result := range results {
		sum += result
	}
	fmt.Printf("Ran %d queries through a pool of at most %d connections\n", queries, poolSize)
	fmt.Printf("Sum of results: %d\n", sum)
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
