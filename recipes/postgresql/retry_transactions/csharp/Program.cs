/*
 * Ellie's Postgres Cookbook
 * Retrying a transaction after a serialisation failure, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Data;
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
const int MaxAttempts = 5;

// Returns true if a SQLSTATE code means "run the transaction again": 40001
// is a serialisation failure and 40P01 is a deadlock.
static bool IsRetryable(string? sqlState) => sqlState is "40001" or "40P01";

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
// OpenConnectionAsync borrows one from the pool, which also gives the
// program a second connection when it needs one. A connection runs each
// statement in its own transaction unless the program begins one.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:setup]
// Drops the shared counter table if it exists.
static async Task DropTableAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "DROP TABLE IF EXISTS cookbook_retry_transactions", conn);
    await cmd.ExecuteNonQueryAsync();
}

// Creates the shared counter table, with a single row set to zero. The
// table must be visible to a second connection, so it cannot be
// temporary; the name is specific to this recipe, and any earlier copy is
// dropped first.
static async Task CreateTableAsync(NpgsqlConnection conn)
{
    await DropTableAsync(conn);

    await using var create = new NpgsqlCommand(
        "CREATE TABLE cookbook_retry_transactions " +
        "(id int PRIMARY KEY, value int NOT NULL)", conn);
    await create.ExecuteNonQueryAsync();

    await using var insert = new NpgsqlCommand(
        "INSERT INTO cookbook_retry_transactions (id, value) " +
        "VALUES ($1, $2)", conn)
    {
        Parameters = { new() { Value = 1 }, new() { Value = 0 } },
    };
    await insert.ExecuteNonQueryAsync();
}
// --8<-- [end:setup]

// --8<-- [start:work]
// Reads the counter and writes back the value plus one.
static async Task IncrementCounterAsync(
    NpgsqlDataSource dataSource, NpgsqlConnection conn, int attempt)
{
    var value = await ReadCounterAsync(conn);

    // Simulate another client by updating the row from a second
    // connection, after this transaction has read the row but before it
    // writes. This happens on the first attempt only.
    if (attempt == 1)
    {
        await using var other = await dataSource.OpenConnectionAsync();
        await using var cmd = new NpgsqlCommand(
            "UPDATE cookbook_retry_transactions SET value = value + 1 " +
            "WHERE id = $1", other)
        {
            Parameters = { new() { Value = 1 } },
        };
        await cmd.ExecuteNonQueryAsync();
    }

    // Under REPEATABLE READ, updating a row that another transaction
    // changed and committed since this transaction's snapshot was taken
    // fails with SQLSTATE 40001.
    await using var update = new NpgsqlCommand(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        conn)
    {
        Parameters = { new() { Value = value + 1 }, new() { Value = 1 } },
    };
    await update.ExecuteNonQueryAsync();
}

// Returns the current value of the counter.
static async Task<int> ReadCounterAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1", conn)
    {
        Parameters = { new() { Value = 1 } },
    };
    return (int)(await cmd.ExecuteScalarAsync())!;
}
// --8<-- [end:work]

// --8<-- [start:retry]
// Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs it
// again if the server reports a serialisation failure or a deadlock.
static async Task RunWithRetryAsync(
    NpgsqlConnection conn, Func<NpgsqlConnection, int, Task> work)
{
    for (var attempt = 1; attempt <= MaxAttempts; attempt++)
    {
        try
        {
            // Disposing the transaction without committing rolls it
            // back, so an error from the work leaves nothing behind.
            await using var tx = await conn.BeginTransactionAsync(
                IsolationLevel.RepeatableRead);
            await work(conn, attempt);
            await tx.CommitAsync();

            Console.WriteLine($"Attempt {attempt}: committed");
            return;
        }
        // Any other error, or running out of attempts, is a real failure
        // that the caller must handle, so the filter lets it through.
        catch (PostgresException e)
            when (IsRetryable(e.SqlState) && attempt < MaxAttempts)
        {
            Console.WriteLine(
                $"Attempt {attempt}: serialisation failure, retrying");
            // A short, growing pause gives the competing transaction time
            // to finish.
            await Task.Delay(50 * attempt);
        }
    }
}
// --8<-- [end:retry]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    try
    {
        await CreateTableAsync(conn);
        await RunWithRetryAsync(
            conn, (c, attempt) => IncrementCounterAsync(dataSource, c, attempt));
        Console.WriteLine($"Counter value: {await ReadCounterAsync(conn)}");
    }
    finally
    {
        // Drop the shared table even if the work failed.
        await DropTableAsync(conn);
    }
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
