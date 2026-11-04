/*
 * Ellie's Postgres Cookbook
 * Reading a large result in batches, using Npgsql.
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
// builder takes care of quoting any special characters.
static string ConnectionString() =>
    new NpgsqlConnectionStringBuilder
    {
        Host = EnvOr("PGHOST", "localhost"),
        Port = int.Parse(EnvOr("PGPORT", "5432")),
        Database = EnvOr("PGDATABASE", "postgres"),
        Username = EnvOr("PGUSER", "postgres"),
        Password = EnvValue("PGPASSWORD"),
    }.ConnectionString;
// --8<-- [end:config]

// --8<-- [start:connect]
// Creates a data source with the settings from the environment. A data
// source manages a pool of physical connections, and each call to
// OpenConnectionAsync borrows one from the pool; an application normally
// creates one data source at start-up and shares it.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:read_batches]
// Reads every row of a large result, and returns the number of rows and
// the sum of their values.
static async Task<(long RowsRead, long Total)> ReadRowsAsync(
    NpgsqlConnection conn)
{
    long rowsRead = 0;
    long total = 0;

    await using var cmd = new NpgsqlCommand(
        "SELECT g FROM generate_series(1, 100000) AS g", conn);

    // ExecuteReaderAsync does not load the result into memory. Npgsql
    // reads rows from the network as ReadAsync asks for them, so the
    // program holds one row at a time; there is no batch size to set,
    // because the connection's read buffer takes the place of the batch.
    await using var reader = await cmd.ExecuteReaderAsync();

    // ReadAsync returns false once the result is exhausted.
    while (await reader.ReadAsync())
    {
        rowsRead++;
        total += reader.GetInt32(0);
    }

    return (rowsRead, total);
}
// --8<-- [end:read_batches]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    var (rowsRead, total) = await ReadRowsAsync(conn);
    Console.WriteLine($"Rows read: {rowsRead}");
    Console.WriteLine($"Sum of values: {total}");
}
// NpgsqlException covers connection failures; PostgresException, which
// derives from it, carries errors reported by the server.
catch (NpgsqlException e)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    return 1;
}

return 0;
// --8<-- [end:main]
