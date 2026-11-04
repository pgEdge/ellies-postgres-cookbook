// Ellie's Postgres Cookbook
// Connecting to PostgreSQL over TLS with full verification, using pgx.
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
// the user name, password, or database name. PGSSLROOTCERT has no
// default, because verification is meaningless without the certificate
// of the authority that signed the server certificate.
func connString() (string, error) {
	rootCert := os.Getenv("PGSSLROOTCERT")
	if rootCert == "" {
		return "", errors.New("PGSSLROOTCERT must name the root certificate")
	}

	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
		// verify-full checks that the certificate chains to the root
		// certificate and that it matches the host name. Weaker modes,
		// such as require, encrypt the connection without proving who
		// is on the other end.
		RawQuery: url.Values{
			"sslmode":     {"verify-full"},
			"sslrootcert": {rootCert},
		}.Encode(),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String(), nil
}

// --8<-- [end:config]

// --8<-- [start:connect]
// connect opens a verified TLS connection with the settings from the
// environment. The connection fails if verification fails.
func connect(ctx context.Context) (*pgx.Conn, error) {
	dsn, err := connString()
	if err != nil {
		return nil, err
	}
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:query]
// connectionIsEncrypted asks the server whether this connection uses TLS.
func connectionIsEncrypted(ctx context.Context, conn *pgx.Conn) (bool, error) {
	// pg_stat_ssl has one row for each connection; pg_backend_pid()
	// identifies the one that belongs to this session. The version column
	// holds the protocol version, such as TLSv1.3, and is NULL without
	// TLS, so it scans into a pointer.
	var ssl bool
	var version *string
	err := conn.QueryRow(ctx,
		"SELECT ssl, version FROM pg_catalog.pg_stat_ssl "+
			"WHERE pid = pg_backend_pid()",
	).Scan(&ssl, &version)
	if err != nil {
		return false, fmt.Errorf("query failed: %w", err)
	}
	return ssl, nil
}

// --8<-- [end:query]

// --8<-- [start:main]
// run connects, runs the query, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	encrypted, err := connectionIsEncrypted(ctx, conn)
	if err != nil {
		return err
	}

	fmt.Printf("Connection is encrypted: %t\n", encrypted)
	// Reaching this line means that verify-full succeeded; a certificate
	// or host name mismatch makes connect() return an error instead.
	fmt.Println("Server certificate verified: true")
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
