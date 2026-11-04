/*
 * Ellie's Postgres Cookbook
 * Passing a list of values as a single array parameter, using Npgsql.
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

// --8<-- [start:query]
// Returns the names from the list that exist as data types.
static async Task<List<string>> FindTypesAsync(
    NpgsqlConnection conn, string[] names)
{
    // The whole list travels as one array parameter, so the SQL text is
    // the same however many values the list holds. Npgsql converts a .NET
    // array into a PostgreSQL array.
    await using var cmd = new NpgsqlCommand(
        "SELECT typname FROM pg_catalog.pg_type " +
        "WHERE typname = ANY($1) ORDER BY typname", conn)
    {
        Parameters = { new() { Value = names } },
    };

    await using var reader = await cmd.ExecuteReaderAsync();
    var found = new List<string>();
    while (await reader.ReadAsync())
    {
        found.Add(reader.GetString(0));
    }
    return found;
}
// --8<-- [end:query]

// --8<-- [start:main]
try
{
    string[] wanted = ["int4", "text", "bool", "no_such_type"];

    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    var found = await FindTypesAsync(conn, wanted);
    Console.WriteLine(
        $"Found {found.Count} of {wanted.Length} types: " +
        string.Join(", ", found));
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
