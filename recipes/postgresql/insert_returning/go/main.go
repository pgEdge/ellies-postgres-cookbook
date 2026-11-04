// Ellie's Postgres Cookbook
// Inserting rows and reading generated keys, using pgx.
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

// --8<-- [start:setup]
// createPeople creates a temporary table whose id column the server fills
// in. GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
// sequence, and refuses any attempt to supply one.
func createPeople(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx,
		"CREATE TEMPORARY TABLE people ("+
			"id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "+
			"name text NOT NULL)")
	if err != nil {
		return fmt.Errorf("create table failed: %w", err)
	}
	return nil
}

// --8<-- [end:setup]

// --8<-- [start:add_person]
// addPerson inserts a row and returns the id that the server generated.
func addPerson(ctx context.Context, conn *pgx.Conn, name string) (int, error) {
	// RETURNING makes the INSERT produce a result row, like a SELECT, so
	// the program learns the new id without a second query. The name is a
	// parameter, which pgx sends separately from the SQL text.
	var id int
	err := conn.QueryRow(ctx,
		"INSERT INTO people (name) VALUES ($1) RETURNING id",
		name,
	).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("insert failed: %w", err)
	}
	return id, nil
}

// --8<-- [end:add_person]

// --8<-- [start:main]
// run connects, inserts the rows, and prints their ids, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	if err := createPeople(ctx, conn); err != nil {
		return err
	}
	for _, name := range []string{"Jane Doe", "John Smith", "Alex Example"} {
		id, err := addPerson(ctx, conn, name)
		if err != nil {
			return err
		}
		fmt.Printf("Inserted '%s' with id %d\n", name, id)
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
