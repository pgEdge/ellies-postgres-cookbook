/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL and running a scalar query, using Npgsql.
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

// Build a connection string from the standard libpq environment
// variables, with defaults suitable for a local development server. The
// builder takes care of quoting any special characters.
var builder = new NpgsqlConnectionStringBuilder
{
    Host = EnvOr("PGHOST", "localhost"),
    Port = int.Parse(EnvOr("PGPORT", "5432")),
    Database = EnvOr("PGDATABASE", "postgres"),
    Username = EnvOr("PGUSER", "postgres"),
    Password = EnvValue("PGPASSWORD"),
};
// --8<-- [end:config]

try
{
    // --8<-- [start:connect]
    // A data source manages a pool of physical connections; opening a
    // connection borrows one from the pool. await using returns it when
    // the enclosing block exits, whether or not an error occurred.
    await using var dataSource = NpgsqlDataSource.Create(builder.ConnectionString);
    await using var conn = await dataSource.OpenConnectionAsync();
    // --8<-- [end:connect]

    // --8<-- [start:query]
    // Always pass values as parameters rather than building them into the
    // SQL string; Npgsql sends them separately, which prevents SQL
    // injection. Positional parameters are written $1, $2, and so on.
    await using var cmd = new NpgsqlCommand(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1", conn)
    {
        Parameters = { new() { Value = "int4" } },
    };

    // ExecuteScalarAsync returns the first column of the first row. A
    // bigint maps to long.
    var count = (long)(await cmd.ExecuteScalarAsync())!;

    Console.WriteLine($"Number of types named 'int4': {count}");
    // --8<-- [end:query]
}
// --8<-- [start:errors]
// NpgsqlException covers connection failures; PostgresException, which
// derives from it, carries errors reported by the server.
catch (NpgsqlException e)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    return 1;
}
// --8<-- [end:errors]

return 0;
