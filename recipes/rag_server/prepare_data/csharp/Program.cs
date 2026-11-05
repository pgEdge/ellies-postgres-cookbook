/*
 * Ellie's Postgres Cookbook
 * Preparing documents for the pgEdge RAG Server: embedding them with
 * Ollama and storing them in a pgvector table, using HttpClient,
 * System.Text.Json and Npgsql.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
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

static string OllamaUrl() =>
    EnvOr("OLLAMA_URL", "http://localhost:11434").TrimEnd('/');
static string EmbedModel() => EnvOr("EMBED_MODEL", "nomic-embed-text");

// This recipe uses its own table, so that it never disturbs the table that
// a running pipeline reads.
const string Table = "cookbook_prepare_data";

// The documents to store; in a real application they come from your own
// data. The text is fictional.
Document[] documents =
[
    new(1, "Charging the Acme Gadget",
        "The Acme Gadget charges through its USB-C port. A full charge takes " +
        "two hours, and a fully charged Acme Gadget runs for ten hours."),
    new(2, "Resetting the Acme Gadget",
        "To reset the Acme Gadget to its factory settings, hold down the " +
        "power button for eight seconds until the status light flashes red."),
    new(3, "Warranty for the Acme Gadget",
        "The Acme Gadget comes with a two-year warranty that covers " +
        "manufacturing defects but not accidental damage."),
];

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

// --8<-- [start:embed]
// Asks Ollama for the embedding of each text, in the same order. pgvector
// stores single-precision values, so a float loses nothing that the table
// would keep.
static async Task<float[][]> EmbedAsync(string[] texts)
{
    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
    // The embed endpoint accepts a list of texts, so one request embeds
    // every document.
    using var response = await client.PostAsJsonAsync(
        $"{OllamaUrl()}/api/embed", new { model = EmbedModel(), input = texts });

    // HttpClient treats an error status as a normal response, so check it
    // here.
    if (!response.IsSuccessStatusCode)
    {
        var body = (await response.Content.ReadAsStringAsync()).Trim();
        throw new EmbedException(
            $"Ollama returned HTTP {(int)response.StatusCode}: " +
            body[..Math.Min(body.Length, 200)]);
    }

    // ReadFromJsonAsync matches the embeddings field to the Embeddings
    // property without regard to case, and leaves it null if it is missing.
    var reply = await response.Content.ReadFromJsonAsync<EmbedReply>();
    if (reply?.Embeddings is not { } embeddings || embeddings.Length != texts.Length)
    {
        throw new EmbedException(
            $"Expected {texts.Length} embeddings, got {reply?.Embeddings?.Length ?? 0}");
    }
    return embeddings;
}
// --8<-- [end:embed]

// --8<-- [start:table]
// Creates the table, replacing any earlier copy. The vector column must
// have the same number of dimensions as the embedding model.
static async Task CreateTableAsync(NpgsqlConnection conn, int dimensions)
{
    await using var cmd = conn.CreateCommand();
    cmd.CommandText = "CREATE EXTENSION IF NOT EXISTS vector";
    await cmd.ExecuteNonQueryAsync();
    cmd.CommandText = $"DROP TABLE IF EXISTS {Table}";
    await cmd.ExecuteNonQueryAsync();
    // The table name is a constant and the dimensions are an int, so
    // building them into the statement is safe; a statement cannot take
    // either as a parameter.
    cmd.CommandText = $"""
        CREATE TABLE {Table} (
            id        integer PRIMARY KEY,
            title     text NOT NULL,
            content   text NOT NULL,
            embedding vector({dimensions}) NOT NULL
        )
        """;
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:table]

// --8<-- [start:insert]
// Stores each document with its embedding.
static async Task InsertDocumentsAsync(
    NpgsqlConnection conn, Document[] documents, float[][] embeddings)
{
    for (var i = 0; i < documents.Length; i++)
    {
        // pgvector reads a vector from text such as '[0.1,0.2,0.3]'. The
        // invariant culture always writes a full stop as the decimal
        // separator, and the cast tells the server how to interpret the
        // parameter.
        var vector = "[" + string.Join(",", embeddings[i].Select(
            value => value.ToString(CultureInfo.InvariantCulture))) + "]";
        await using var cmd = new NpgsqlCommand(
            $"INSERT INTO {Table} (id, title, content, embedding) " +
            "VALUES ($1, $2, $3, $4::vector)", conn)
        {
            Parameters =
            {
                new() { Value = documents[i].Id },
                new() { Value = documents[i].Title },
                new() { Value = documents[i].Content },
                new() { Value = vector },
            },
        };
        await cmd.ExecuteNonQueryAsync();
    }
}
// --8<-- [end:insert]

// --8<-- [start:verify]
// Returns the number of rows, and the number of dimensions of their
// embeddings. count(*) returns a bigint, which maps to long, and
// vector_dims() returns an integer, which maps to int.
static async Task<(long Rows, int Dimensions)> DescribeTableAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        $"SELECT count(*), max(vector_dims(embedding)) FROM {Table}", conn);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return (reader.GetInt64(0), reader.GetInt32(1));
}
// --8<-- [end:verify]

// --8<-- [start:cleanup]
// Removes the table. A real application keeps it, so that the RAG Server
// can read it.
static async Task DropTableAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand($"DROP TABLE IF EXISTS {Table}", conn);
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:cleanup]

// --8<-- [start:main]
var cleanupFailed = false;
try
{
    var embeddings = await EmbedAsync([.. documents.Select(doc => doc.Content)]);
    Console.WriteLine($"Embedded {embeddings.Length} documents with {EmbedModel()}");

    // await using disposes of the data source and the connection when the
    // block exits, whether or not an error occurred.
    await using var dataSource = NpgsqlDataSource.Create(ConnectionString());
    await using var conn = await dataSource.OpenConnectionAsync();
    try
    {
        // Disposing of a transaction that has not been committed rolls it
        // back, so a failed step undoes every step before it.
        await using (var tx = await conn.BeginTransactionAsync())
        {
            await CreateTableAsync(conn, embeddings[0].Length);
            await InsertDocumentsAsync(conn, documents, embeddings);
            await tx.CommitAsync();
        }

        var (rows, dimensions) = await DescribeTableAsync(conn);
        Console.WriteLine(
            $"Stored {rows} rows with {dimensions}-dimension embeddings in {Table}");
    }
    finally
    {
        // Remove the table whether or not a step failed. A failure here is
        // reported on its own, so that it cannot hide the error that came
        // first.
        try
        {
            await DropTableAsync(conn);
        }
        catch (NpgsqlException e)
        {
            Console.Error.WriteLine($"Cleanup error: {e.Message}");
            cleanupFailed = true;
        }
    }
}
// HttpRequestException covers failures to reach Ollama, such as a refused
// connection, TaskCanceledException covers a timeout, JsonException covers
// a reply that is not JSON, and NpgsqlException covers connection failures
// and errors reported by the server.
catch (Exception e) when (e is HttpRequestException or TaskCanceledException
    or JsonException or NpgsqlException or EmbedException)
{
    Console.Error.WriteLine($"Error: {e.Message}");
    return 1;
}

return cleanupFailed ? 1 : 0;

// C# requires type declarations to follow the top-level statements, so the
// types that the program uses are declared here, at the end.

// A row to store.
record Document(int Id, string Title, string Content);

// The part of Ollama's reply that the program reads.
record EmbedReply(float[][]? Embeddings);

// Thrown when Ollama rejects a request or returns an unexpected reply.
class EmbedException(string message) : Exception(message);
// --8<-- [end:main]
