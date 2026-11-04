/*
 * Ellie's Postgres Cookbook
 * Storing and searching vectors with pgvector, using Npgsql.
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
// OpenConnectionAsync borrows one from the pool. This program borrows a
// single connection and uses it throughout, because a temporary table
// belongs to one session.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:schema]
// Enables pgvector and creates a temporary table of colours.
static async Task CreateSchemaAsync(NpgsqlConnection conn)
{
    // vector(3) fixes the number of dimensions, one for each of the red,
    // green, and blue components. The temporary table disappears when the
    // session ends, so the program can run repeatedly. An HNSW index
    // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
    // (Euclidean distance) operator used by the search.
    string[] statements =
    [
        "CREATE EXTENSION IF NOT EXISTS vector",
        "CREATE TEMPORARY TABLE colours (" +
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
        "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
    ];
    foreach (var statement in statements)
    {
        await using var cmd = new NpgsqlCommand(statement, conn);
        await cmd.ExecuteNonQueryAsync();
    }
}
// --8<-- [end:schema]

// --8<-- [start:insert]
// Stores five colours, each as a vector of its RGB components.
static async Task InsertColoursAsync(NpgsqlConnection conn)
{
    (string Name, string Rgb)[] colours =
    [
        ("red", "[1,0,0]"),
        ("green", "[0,1,0]"),
        ("blue", "[0,0,1]"),
        ("yellow", "[1,1,0]"),
        ("white", "[1,1,1]"),
    ];
    foreach (var (name, rgb) in colours)
    {
        // A vector travels as text in pgvector's [x,y,z] format, and the
        // ::vector cast converts it on the server, so Npgsql needs no
        // vector-specific support. Positional parameters are written $1,
        // $2, and so on.
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)", conn)
        {
            Parameters = { new() { Value = name }, new() { Value = rgb } },
        };
        await cmd.ExecuteNonQueryAsync();
    }
}
// --8<-- [end:insert]

// --8<-- [start:search]
// Returns the names of the colours nearest to the target vector.
static async Task<List<string>> NearestColoursAsync(
    NpgsqlConnection conn, string target, int count)
{
    // <-> is the Euclidean (L2) distance operator, so ordering by it puts
    // the nearest colour first.
    await using var cmd = new NpgsqlCommand(
        "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
        conn)
    {
        Parameters = { new() { Value = target }, new() { Value = count } },
    };

    var names = new List<string>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        names.Add(reader.GetString(0));
    }
    return names;
}
// --8<-- [end:search]

// --8<-- [start:main]
try
{
    const string target = "[0.9,0.7,0.2]";

    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();
    await CreateSchemaAsync(conn);
    await InsertColoursAsync(conn);

    Console.WriteLine($"Colours nearest to {target}:");
    var names = await NearestColoursAsync(conn, target, 3);
    for (var i = 0; i < names.Count; i++)
    {
        Console.WriteLine($"{i + 1}. {names[i]}");
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
