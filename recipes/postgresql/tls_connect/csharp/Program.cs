/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL over TLS with full verification, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or null if the variable
// is unset or empty; libpq also treats an empty variable as unset.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Returns the value of an environment variable, or a fallback if unset.
static string EnvOr(string name, string fallback) =>
    EnvValue(name) ?? fallback;

// Builds a connection string from the standard libpq environment
// variables, with defaults suitable for a local development server. The
// builder takes care of quoting any special characters. PGSSLROOTCERT has
// no default, because verification is meaningless without the certificate
// of the authority that signed the server certificate.
static string ConnectionString() =>
    new NpgsqlConnectionStringBuilder
    {
        Host = EnvOr("PGHOST", "localhost"),
        Port = int.Parse(EnvOr("PGPORT", "5432")),
        Database = EnvOr("PGDATABASE", "postgres"),
        Username = EnvOr("PGUSER", "postgres"),
        Password = EnvValue("PGPASSWORD"),
        // VerifyFull checks that the certificate chains to the root
        // certificate and that it matches the host name. Weaker modes,
        // such as Require, encrypt the connection without proving who is
        // on the other end.
        SslMode = SslMode.VerifyFull,
        RootCertificate = EnvValue("PGSSLROOTCERT")
            ?? throw new InvalidOperationException(
                "PGSSLROOTCERT must name the root certificate"),
    }.ConnectionString;
// --8<-- [end:config]

// --8<-- [start:connect]
// Creates a data source with the settings from the environment. A data
// source manages a pool of physical connections, and each call to
// OpenConnectionAsync borrows one from the pool; the connection fails if
// verification fails.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:query]
// Asks the server whether this connection uses TLS.
static async Task<bool> ConnectionIsEncryptedAsync(NpgsqlConnection conn)
{
    // pg_stat_ssl has one row for each connection; pg_backend_pid()
    // identifies the one that belongs to this session. The version column
    // holds the protocol version, such as TLSv1.3.
    await using var cmd = new NpgsqlCommand(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
        "WHERE pid = pg_backend_pid()", conn);
    await using var reader = await cmd.ExecuteReaderAsync();

    // A boolean maps to bool.
    await reader.ReadAsync();
    return reader.GetBoolean(0);
}
// --8<-- [end:query]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    var encrypted = await ConnectionIsEncryptedAsync(conn);
    Console.WriteLine($"Connection is encrypted: {encrypted.ToString().ToLowerInvariant()}");
    // Reaching this line means that VerifyFull succeeded; a certificate
    // or host name mismatch throws instead.
    Console.WriteLine("Server certificate verified: true");
}
// NpgsqlException covers connection failures; PostgresException, which
// derives from it, carries errors reported by the server.
// InvalidOperationException reports a missing PGSSLROOTCERT.
catch (Exception e) when (e is NpgsqlException or InvalidOperationException)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    return 1;
}

return 0;
// --8<-- [end:main]
