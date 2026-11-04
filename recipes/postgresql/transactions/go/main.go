// Ellie's Postgres Cookbook
// Using transactions to move money between accounts, using pgx.
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
// createAccounts creates a temporary table of two accounts. The CHECK
// constraint stops any balance from going below zero.
func createAccounts(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx,
		"CREATE TEMPORARY TABLE accounts ("+
			"id int PRIMARY KEY, "+
			"balance int NOT NULL CHECK (balance >= 0))")
	if err != nil {
		return fmt.Errorf("create table failed: %w", err)
	}
	_, err = conn.Exec(ctx, "INSERT INTO accounts VALUES (1, 100), (2, 50)")
	if err != nil {
		return fmt.Errorf("insert failed: %w", err)
	}
	return nil
}

// --8<-- [end:setup]

// --8<-- [start:transfer]
// transfer moves money between two accounts in a single transaction.
func transfer(ctx context.Context, conn *pgx.Conn, source, target, amount int) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin failed: %w", err)
	}
	// Rollback does nothing once the transaction has committed, so the
	// deferred call undoes the work only if a statement fails first.
	defer tx.Rollback(ctx)

	// Credit the target first, so that a failure of the debit shows that
	// the rollback undoes the credit as well.
	_, err = tx.Exec(ctx,
		"UPDATE accounts SET balance = balance + $1 WHERE id = $2",
		amount, target)
	if err != nil {
		return fmt.Errorf("credit failed: %w", err)
	}
	_, err = tx.Exec(ctx,
		"UPDATE accounts SET balance = balance - $1 WHERE id = $2",
		amount, source)
	if err != nil {
		return fmt.Errorf("debit failed: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit failed: %w", err)
	}
	return nil
}

// --8<-- [end:transfer]

// --8<-- [start:balance]
// getBalance returns the balance of the given account.
func getBalance(ctx context.Context, conn *pgx.Conn, account int) (int, error) {
	var balance int
	err := conn.QueryRow(ctx,
		"SELECT balance FROM accounts WHERE id = $1", account,
	).Scan(&balance)
	if err != nil {
		return 0, fmt.Errorf("query failed: %w", err)
	}
	return balance, nil
}

// --8<-- [end:balance]

// --8<-- [start:main]
// isCheckViolation reports whether err is a check constraint violation,
// which is SQLSTATE 23514.
func isCheckViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23514"
}

// run connects, makes the transfers, and prints the balances, returning
// any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	if err := createAccounts(ctx, conn); err != nil {
		return err
	}

	if err := transfer(ctx, conn, 1, 2, 30); err != nil {
		return err
	}
	fmt.Println("Transferred 30 from account 1 to account 2")

	// The transaction has already been rolled back, so a check violation
	// is an expected outcome; any other error is not, and is returned.
	err = transfer(ctx, conn, 1, 2, 500)
	switch {
	case err == nil:
		fmt.Println("Transferred 500 from account 1 to account 2")
	case isCheckViolation(err):
		fmt.Println("Transfer of 500 from account 1 to account 2 failed and was rolled back")
	default:
		return err
	}

	for _, account := range []int{1, 2} {
		balance, err := getBalance(ctx, conn, account)
		if err != nil {
			return err
		}
		fmt.Printf("Account %d balance: %d\n", account, balance)
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
