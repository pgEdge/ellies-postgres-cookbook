/*
 * Ellie's Postgres Cookbook
 * Using a connection pool, with Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
// The most connections that the pool opens at any one time.
const int PoolSize = 2;

// Returns the value of an environment variable, or null if the variable
// is unset or empty; libpq also treats an empty variable as unset.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Returns the value of an environment variable, or a fallback if unset.
static string EnvOr(string name, string fallback) =>
    EnvValue(name) ?? fallback;
// --8<-- [end:config]

// --8<-- [start:pool]
// Creates a data source, which owns a pool that holds at most PoolSize
// connections. Npgsql pools connections by default; the connection string
// builder sets the limits and takes care of quoting any special
// characters in the settings.
static NpgsqlDataSource CreatePool() =>
    NpgsqlDataSource.Create(new NpgsqlConnectionStringBuilder
    {
        Host = EnvOr("PGHOST", "localhost"),
        Port = int.Parse(EnvOr("PGPORT", "5432")),
        Database = EnvOr("PGDATABASE", "postgres"),
        Username = EnvOr("PGUSER", "postgres"),
        Password = EnvValue("PGPASSWORD"),
        MaxPoolSize = PoolSize,

        // A request for a connection fails after this many seconds if
        // the pool can neither lend an idle connection nor open a new one.
        Timeout = 5,
    }.ConnectionString);
// --8<-- [end:pool]

// --8<-- [start:query]
// Borrows a connection from the pool, and returns the number back.
static async Task<int> RunQueryAsync(NpgsqlDataSource pool, int number)
{
    // await using returns the connection to the pool when the method
    // exits, whether or not an error occurred; disposing of a pooled
    // connection does not disconnect it from the server.
    await using var conn = await pool.OpenConnectionAsync();

    // Pass values as parameters rather than building them into the SQL
    // string. Positional parameters are written $1, $2, and so on. The
    // cast gives the parameter a type, which the server cannot infer from
    // SELECT $1 alone.
    await using var cmd = new NpgsqlCommand("SELECT $1::int", conn)
    {
        Parameters = { new() { Value = number } },
    };
    return (int)(await cmd.ExecuteScalarAsync())!;
}
// --8<-- [end:query]

// --8<-- [start:main]
try
{
    // await using closes the pool, and every connection in it, when the
    // block exits, whether or not an error occurred.
    await using var pool = CreatePool();

    // Five tasks ask for a connection at once, but the pool has only two,
    // so the other tasks wait their turn.
    var results = await Task.WhenAll(
        Enumerable.Range(1, 5).Select(n => RunQueryAsync(pool, n)));

    Console.WriteLine($"Ran {results.Length} queries through a pool of " +
                      $"at most {PoolSize} connections");
    Console.WriteLine($"Sum of results: {results.Sum()}");
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
