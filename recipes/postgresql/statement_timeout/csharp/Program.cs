/*
 * Ellie's Postgres Cookbook
 * Setting a server-side statement timeout, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
// The SQLSTATE code that the server reports when it cancels a statement,
// whether because of a timeout or because a client asked for the cancel.
const string QueryCanceled = "57014";

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
// OpenConnectionAsync borrows one from the pool. A connection runs each
// statement in its own transaction unless the program begins one, so a
// cancelled statement does not leave the session in a failed transaction.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:timeout]
// Sets the statement timeout for the rest of the session.
static async Task SetStatementTimeoutAsync(NpgsqlConnection conn, string timeout)
{
    // SET cannot take a parameter, but set_config() is an ordinary
    // function, so the value can be sent safely. The final argument,
    // false, makes the setting last for the session rather than for the
    // current transaction.
    await using var cmd = new NpgsqlCommand(
        "SELECT set_config('statement_timeout', $1, false)", conn)
    {
        Parameters = { new() { Value = timeout } },
    };
    await cmd.ExecuteNonQueryAsync();
}

// Runs a statement that outlasts the timeout, and returns true if the
// server cancelled it.
static async Task<bool> SleepExceedsTimeoutAsync(NpgsqlConnection conn)
{
    try
    {
        await using var cmd = new NpgsqlCommand("SELECT pg_sleep(5)", conn);
        await cmd.ExecuteNonQueryAsync();
        return false;
    }
    // Only a cancelled statement is expected here; the filter lets any
    // other error through to the caller.
    catch (PostgresException e) when (e.SqlState == QueryCanceled)
    {
        return true;
    }
}

// Returns true if the session can still run a statement.
static async Task<bool> IsUsableAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand("SELECT 1", conn);
    return (int)(await cmd.ExecuteScalarAsync())! == 1;
}
// --8<-- [end:timeout]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    await SetStatementTimeoutAsync(conn, "100ms");
    if (await SleepExceedsTimeoutAsync(conn))
    {
        Console.WriteLine("Query cancelled after exceeding the statement timeout");
    }

    var usable = await IsUsableAsync(conn);
    Console.WriteLine($"Connection still usable: {usable.ToString().ToLowerInvariant()}");
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
