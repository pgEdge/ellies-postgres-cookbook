// Ellie's Postgres Cookbook
// Setting a server-side statement timeout, using pgx.
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

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// queryCanceled is the SQLSTATE code that the server reports when it
// cancels a statement, whether because of a timeout or because a client
// asked for the cancel.
const queryCanceled = "57014"

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
// connect opens a connection with the settings from the environment. pgx
// runs each statement in its own transaction unless the program begins
// one, so a cancelled statement does not leave the session in a failed
// transaction.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:timeout]
// setStatementTimeout sets the statement timeout for the rest of the
// session.
func setStatementTimeout(ctx context.Context, conn *pgx.Conn, timeout string) error {
	// SET cannot take a parameter, but set_config() is an ordinary
	// function, so the value can be sent safely. The final argument,
	// false, makes the setting last for the session rather than for the
	// current transaction.
	_, err := conn.Exec(ctx,
		"SELECT set_config('statement_timeout', $1, false)", timeout)
	return err
}

// sleepExceedsTimeout runs a statement that outlasts the timeout, and
// returns true if the server cancelled it.
func sleepExceedsTimeout(ctx context.Context, conn *pgx.Conn) (bool, error) {
	_, err := conn.Exec(ctx, "SELECT pg_sleep(5)")
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == queryCanceled {
		return true, nil
	}
	// Only a cancelled statement is expected here; any other error is a
	// real failure, so it is returned.
	return false, err
}

// isUsable returns true if the session can still run a statement.
func isUsable(ctx context.Context, conn *pgx.Conn) (bool, error) {
	var one int
	err := conn.QueryRow(ctx, "SELECT 1").Scan(&one)
	return one == 1, err
}

// --8<-- [end:timeout]

// --8<-- [start:main]
// run connects, sets the timeout, runs the slow statement, and prints the
// results, returning any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	if err := setStatementTimeout(ctx, conn, "100ms"); err != nil {
		return err
	}

	cancelled, err := sleepExceedsTimeout(ctx, conn)
	if err != nil {
		return err
	}
	if cancelled {
		fmt.Println("Query cancelled after exceeding the statement timeout")
	}

	usable, err := isUsable(ctx, conn)
	if err != nil {
		return err
	}
	fmt.Printf("Connection still usable: %t\n", usable)
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
