// Ellie's Postgres Cookbook
// Listening for notifications with LISTEN and NOTIFY, using pgx.
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
const (
	channel = "cookbook_listen_notify"
	timeout = 5 * time.Second
)

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
// runs each statement in autocommit mode unless the program begins a
// transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon as
// the statement completes.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:listen]
// listen subscribes the connection to a channel.
func listen(ctx context.Context, conn *pgx.Conn, channel string) error {
	// LISTEN takes an identifier rather than a value, so it cannot use a
	// parameter; pgx.Identifier quotes the name safely.
	_, err := conn.Exec(ctx, "LISTEN "+pgx.Identifier{channel}.Sanitize())
	if err != nil {
		return fmt.Errorf("listen failed: %w", err)
	}
	return nil
}

// --8<-- [end:listen]

// --8<-- [start:notify]
// notify sends a notification to every connection listening on a channel.
func notify(ctx context.Context, conn *pgx.Conn, channel, payload string) error {
	// pg_notify() takes the channel and payload as ordinary parameters,
	// unlike the NOTIFY command.
	_, err := conn.Exec(ctx, "SELECT pg_notify($1, $2)", channel, payload)
	if err != nil {
		return fmt.Errorf("notify failed: %w", err)
	}
	return nil
}

// --8<-- [end:notify]

// --8<-- [start:wait]
// waitForNotification waits for one notification, and returns it. It
// returns an error if none arrives within the timeout.
func waitForNotification(ctx context.Context, conn *pgx.Conn, timeout time.Duration) (*pgconn.Notification, error) {
	// WaitForNotification blocks until a notification arrives or the
	// context ends, so a context with a deadline provides the timeout.
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	message, err := conn.WaitForNotification(ctx)
	if errors.Is(err, context.DeadlineExceeded) {
		return nil, fmt.Errorf("no notification within %v", timeout)
	}
	if err != nil {
		return nil, fmt.Errorf("wait failed: %w", err)
	}
	return message, nil
}

// --8<-- [end:wait]

// --8<-- [start:main]
// run opens two connections, listens on one, notifies from the other, and
// prints the notification, returning any error to the caller.
func run(ctx context.Context) error {
	listener, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred calls close the connections when run() returns, whether
	// or not an error occurred.
	defer listener.Close(ctx)

	sender, err := connect(ctx)
	if err != nil {
		return err
	}
	defer sender.Close(ctx)

	if err := listen(ctx, listener, channel); err != nil {
		return err
	}
	fmt.Printf("Listening on channel '%s'\n", channel)

	if err := notify(ctx, sender, channel, "Hello from connection B"); err != nil {
		return err
	}

	message, err := waitForNotification(ctx, listener, timeout)
	if err != nil {
		return err
	}
	fmt.Printf("Received notification on '%s': %s\n", message.Channel, message.Payload)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
