/*
 * Ellie's Postgres Cookbook
 * Finding the address of a pgEdge Control Plane database and connecting
 * to it, using HttpClient, System.Text.Json and Npgsql.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or a fallback if the
// variable is unset or empty.
static string? EnvOr(string name, string? fallback) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : fallback;

static string BaseUrl() =>
    EnvOr("CONTROL_PLANE_URL", "http://localhost:3000")!.TrimEnd('/');

// The password has no default; the Control Plane never returns it, so it
// comes from whoever created the database user.
static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;
static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);

const int TimeoutSeconds = 30;

// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Fetches a path from the server, and returns the decoded reply.
static async Task<JsonObject> GetAsync(HttpClient client, string path)
{
    using var response = await client.GetAsync(BaseUrl() + path);
    var body = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
    {
        throw new ControlPlaneException(
            $"HTTP {(int)response.StatusCode}, {Shorten(body)}");
    }
    try
    {
        if (JsonNode.Parse(body) is JsonObject reply)
        {
            return reply;
        }
    }
    catch (JsonException)
    {
        // The body is not JSON; report it below.
    }
    throw new ControlPlaneException($"Unexpected response: {Shorten(body)}");
}
// --8<-- [end:config]

// --8<-- [start:find]
// Returns the connection settings for the first instance of the database
// that is available. Each instance runs one node of the database, and its
// connection_info holds the addresses and port that clients use.
static async Task<Instance> FindInstanceAsync(HttpClient client)
{
    var database = await GetAsync(client, $"/v1/databases/{DatabaseId()}");
    if (database["instances"] is JsonArray instances)
    {
        foreach (var instance in instances)
        {
            var info = instance?["connection_info"];
            if (instance?["state"]?.ToString() == "available" &&
                info?["addresses"] is JsonArray { Count: > 0 } addresses)
            {
                return new Instance(
                    instance["node_name"]?.ToString() ?? "",
                    addresses[0]!.ToString(),
                    info["port"]?.GetValue<int>() ?? 0,
                    database["spec"]?["database_name"]?.ToString() ?? "");
            }
        }
    }
    throw new ControlPlaneException($"no available instance of {DatabaseId()}");
}
// --8<-- [end:find]

// --8<-- [start:connect]
// Connects to the instance, and returns the name of the database and the
// version of the Spock extension. The builder takes care of quoting any
// special characters.
static async Task<(string Database, string Spock)> QueryAsync(Instance instance)
{
    var connectionString = new NpgsqlConnectionStringBuilder
    {
        Host = instance.Host,
        Port = instance.Port,
        Database = instance.Database,
        Username = DatabaseUser(),
        Password = DatabasePassword(),
        Timeout = TimeoutSeconds,
    }.ConnectionString;

    // await using closes the connection and commands when the block
    // exits, whether or not a query failed.
    await using var conn = new NpgsqlConnection(connectionString);
    await conn.OpenAsync();

    await using var databaseCmd = new NpgsqlCommand("SELECT current_database()", conn);
    var database = (string)(await databaseCmd.ExecuteScalarAsync())!;

    await using var spockCmd = new NpgsqlCommand(
        "SELECT extversion FROM pg_extension WHERE extname = 'spock'", conn);
    var spock = await spockCmd.ExecuteScalarAsync() as string ?? "not installed";
    return (database, spock);
}
// --8<-- [end:connect]

// --8<-- [start:main]
if (DatabasePassword() is null)
{
    Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
    return 1;
}

Instance found;
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    found = await FindInstanceAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or ControlPlaneException)
{
    Console.Error.WriteLine($"Control Plane error: {e.Message}");
    return 1;
}
Console.WriteLine($"Connecting to node {found.Node}");

try
{
    var (database, spock) = await QueryAsync(found);
    Console.WriteLine($"Connected to database {database}");
    Console.WriteLine($"Spock: {spock}");
}
// NpgsqlException is the base class for the driver's errors, including
// connection failures and errors reported by the server.
catch (NpgsqlException e)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    return 1;
}
return 0;

// C# requires type declarations to follow the top-level statements, so
// the settings for one instance, and the exception that the program
// throws for an error reply, are declared here, at the end.
record Instance(string Node, string Host, int Port, string Database);

class ControlPlaneException(string message) : Exception(message);
// --8<-- [end:main]
