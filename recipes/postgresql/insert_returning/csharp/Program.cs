/*
 * Ellie's Postgres Cookbook
 * Inserting rows and reading generated keys, using Npgsql.
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
// creates one data source at start-up and shares it. A temporary table
// belongs to one physical connection, so this program borrows a single
// connection and uses it throughout.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:setup]
// Creates a temporary table whose id column the server fills in.
// GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
// sequence, and refuses any attempt to supply one.
static async Task CreatePeopleAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "CREATE TEMPORARY TABLE people (" +
        "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
        "name text NOT NULL)", conn);
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:setup]

// --8<-- [start:add_person]
// Inserts a row and returns the id that the server generated.
static async Task<int> AddPersonAsync(NpgsqlConnection conn, string name)
{
    // RETURNING makes the INSERT produce a result row, like a SELECT, so
    // the program learns the new id without a second query. The name is a
    // parameter, which Npgsql sends separately from the SQL text.
    // Positional parameters are written $1, $2, and so on.
    await using var cmd = new NpgsqlCommand(
        "INSERT INTO people (name) VALUES ($1) RETURNING id", conn)
    {
        Parameters = { new() { Value = name } },
    };

    // ExecuteScalarAsync returns the first column of the first row. An
    // int maps to int.
    return (int)(await cmd.ExecuteScalarAsync())!;
}
// --8<-- [end:add_person]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    await CreatePeopleAsync(conn);
    foreach (var name in new[] { "Jane Doe", "John Smith", "Alex Example" })
    {
        var id = await AddPersonAsync(conn, name);
        Console.WriteLine($"Inserted '{name}' with id {id}");
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
