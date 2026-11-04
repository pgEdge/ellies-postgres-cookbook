/*
 * Ellie's Postgres Cookbook
 * Loading rows in bulk with COPY, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
using NpgsqlTypes;
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

// --8<-- [start:create_table]
// Creates a temporary table, which only this session can see and which
// PostgreSQL drops when the session ends.
static async Task CreateTableAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
        conn);
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:create_table]

// --8<-- [start:generate_rows]
// Returns the rows to load, as (id, name) pairs. The iterator produces
// the rows one at a time, so the program never holds them all.
static IEnumerable<(int Id, string Name)> GenerateRows(int count)
{
    for (var id = 1; id <= count; id++)
    {
        yield return (id, $"item {id}");
    }
}
// --8<-- [end:generate_rows]

// --8<-- [start:copy_rows]
// Loads the rows with COPY ... FROM STDIN and returns how many rows the
// server stored.
static async Task<ulong> CopyRowsAsync(
    NpgsqlConnection conn, IEnumerable<(int Id, string Name)> rows)
{
    // BeginBinaryImport uses the binary COPY format, which sends each
    // value in its native form, so there are no tabs, newlines, or
    // backslashes to escape. COPY is much faster than one INSERT for each
    // row. Disposing of the importer without calling CompleteAsync
    // cancels the copy.
    await using var writer = await conn.BeginBinaryImportAsync(
        "COPY items (id, name) FROM STDIN (FORMAT BINARY)");

    foreach (var (id, name) in rows)
    {
        await writer.StartRowAsync();
        await writer.WriteAsync(id, NpgsqlDbType.Integer);
        await writer.WriteAsync(name, NpgsqlDbType.Text);
    }

    // CompleteAsync finishes the copy, and returns the row count.
    return await writer.CompleteAsync();
}
// --8<-- [end:copy_rows]

// --8<-- [start:summarise]
// Returns the number of rows in the table and the sum of their ids.
static async Task<(long Count, long Total)> SummariseAsync(
    NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "SELECT count(*), sum(id) FROM items", conn);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();

    // count returns a bigint, and sum of an int returns a bigint too;
    // both map to long.
    return (reader.GetInt64(0), reader.GetInt64(1));
}
// --8<-- [end:summarise]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    await CreateTableAsync(conn);

    var copied = await CopyRowsAsync(conn, GenerateRows(1000));
    Console.WriteLine($"Copied {copied} rows");

    var (count, total) = await SummariseAsync(conn);
    Console.WriteLine($"Rows in table: {count}");
    Console.WriteLine($"Sum of ids: {total}");
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
