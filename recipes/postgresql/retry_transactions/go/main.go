// Ellie's Postgres Cookbook
// Retrying a transaction after a serialisation failure, using pgx.
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
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// maxAttempts is the number of times the transaction runs before the
// program gives up.
const maxAttempts = 5

// isRetryable reports whether err carries a SQLSTATE code that means "run
// the transaction again": 40001 is a serialisation failure and 40P01 is a
// deadlock.
func isRetryable(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) &&
		(pgErr.Code == "40001" || pgErr.Code == "40P01")
}

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

// --8<-- [start:setup]
// dropTable drops the shared counter table if it exists.
func dropTable(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS cookbook_retry_transactions")
	return err
}

// createTable creates the shared counter table, with a single row set to
// zero. The table must be visible to a second connection, so it cannot be
// temporary; the name is specific to this recipe, and any earlier copy is
// dropped first.
func createTable(ctx context.Context, conn *pgx.Conn) error {
	if err := dropTable(ctx, conn); err != nil {
		return err
	}
	_, err := conn.Exec(ctx,
		"CREATE TABLE cookbook_retry_transactions "+
			"(id int PRIMARY KEY, value int NOT NULL)")
	if err != nil {
		return err
	}
	_, err = conn.Exec(ctx,
		"INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
		1, 0)
	return err
}

// --8<-- [end:setup]

// --8<-- [start:work]
// incrementCounter reads the counter and writes back the value plus one.
func incrementCounter(ctx context.Context, tx pgx.Tx, attempt int) error {
	var value int
	err := tx.QueryRow(ctx,
		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
		1).Scan(&value)
	if err != nil {
		return err
	}

	// Simulate another client by updating the row from a second
	// connection, after this transaction has read the row but before it
	// writes. This happens on the first attempt only.
	if attempt == 1 {
		if err := updateFromOtherConnection(ctx); err != nil {
			return err
		}
	}

	// Under REPEATABLE READ, updating a row that another transaction
	// changed and committed since this transaction's snapshot was taken
	// fails with SQLSTATE 40001.
	_, err = tx.Exec(ctx,
		"UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
		value+1, 1)
	return err
}

// updateFromOtherConnection increments the counter on a second connection,
// which commits straight away because it has no open transaction.
func updateFromOtherConnection(ctx context.Context) error {
	other, err := connect(ctx)
	if err != nil {
		return err
	}
	defer other.Close(ctx)

	_, err = other.Exec(ctx,
		"UPDATE cookbook_retry_transactions SET value = value + 1 "+
			"WHERE id = $1", 1)
	return err
}

// readCounter returns the current value of the counter.
func readCounter(ctx context.Context, conn *pgx.Conn) (int, error) {
	var value int
	err := conn.QueryRow(ctx,
		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
		1).Scan(&value)
	return value, err
}

// --8<-- [end:work]

// --8<-- [start:retry]
// runOnce runs work in a single REPEATABLE READ transaction.
func runOnce(ctx context.Context, conn *pgx.Conn, attempt int,
	work func(context.Context, pgx.Tx, int) error) error {
	tx, err := conn.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead})
	if err != nil {
		return err
	}
	// The deferred rollback undoes the work if it fails; after a
	// successful commit it does nothing.
	defer tx.Rollback(ctx)

	if err := work(ctx, tx, attempt); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// runWithRetry runs work in a REPEATABLE READ transaction, and runs it
// again if the server reports a serialisation failure or a deadlock.
func runWithRetry(ctx context.Context, conn *pgx.Conn,
	work func(context.Context, pgx.Tx, int) error) error {
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		err := runOnce(ctx, conn, attempt, work)
		if err == nil {
			fmt.Printf("Attempt %d: committed\n", attempt)
			return nil
		}

		// Any other error, or running out of attempts, is a real failure
		// that the caller must handle.
		if !isRetryable(err) || attempt == maxAttempts {
			return err
		}
		fmt.Printf("Attempt %d: serialisation failure, retrying\n", attempt)
		// A short, growing pause gives the competing transaction time to
		// finish.
		time.Sleep(time.Duration(attempt) * 50 * time.Millisecond)
	}
	return nil
}

// --8<-- [end:retry]

// --8<-- [start:main]
// run connects, runs the transaction with retries, and prints the result,
// returning any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	// Drop the shared table when the work is done, even if it failed.
	defer dropTable(ctx, conn)

	if err := createTable(ctx, conn); err != nil {
		return err
	}
	if err := runWithRetry(ctx, conn, incrementCounter); err != nil {
		return err
	}

	value, err := readCounter(ctx, conn)
	if err != nil {
		return err
	}
	fmt.Printf("Counter value: %d\n", value)
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
