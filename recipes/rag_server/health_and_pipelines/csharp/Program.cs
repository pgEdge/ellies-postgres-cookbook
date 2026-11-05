/*
 * Ellie's Postgres Cookbook
 * Checking the health of the pgEdge RAG Server and listing its pipelines,
 * using HttpClient and System.Text.Json.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Text.Json;
using System.Text.Json.Nodes;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or a fallback if the
// variable is unset or empty.
static string EnvOr(string name, string fallback) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : fallback;

static string BaseUrl() =>
    EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');

// None of these endpoints calls a language model, but the health check
// contacts each provider, so allow it some time.
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
        throw new RagException(
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
    throw new RagException($"Unexpected response: {Shorten(body)}");
}
// --8<-- [end:config]

// --8<-- [start:live]
// Checks that the server process is running. The /v1/live endpoint is
// cheap and calls nothing else, so it suits a frequent liveness probe.
static async Task CheckLiveAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/live");
    if (reply["status"]?.ToString() != "ok")
    {
        throw new RagException($"Unexpected response: {reply.ToJsonString()}");
    }
    Console.WriteLine("Live: ok");
}
// --8<-- [end:live]

// --8<-- [start:health]
// Describes whether a language model provider answered the check.
static string DescribeProvider(JsonNode? provider)
{
    if (provider?["reachable"] is JsonValue reachable &&
        reachable.TryGetValue(out bool isReachable) && isReachable)
    {
        return "reachable";
    }
    return $"unreachable ({provider?["error"]?.ToString() ?? "unknown"})";
}

// Checks whether each pipeline can reach its language model providers.
// The /v1/health endpoint answers with HTTP 200 even when a provider is
// down, so the status field is the thing to check: it is "healthy" or
// "degraded". Prints the report, and returns whether the server is
// healthy.
static async Task<bool> CheckHealthAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/health");
    if (reply["status"] is not JsonValue statusNode ||
        !statusNode.TryGetValue(out string? status))
    {
        throw new RagException($"Unexpected response: {reply.ToJsonString()}");
    }

    Console.WriteLine($"Health: {status}");
    if (reply["pipelines"] is JsonArray pipelines)
    {
        foreach (var pipeline in pipelines)
        {
            var embedding = DescribeProvider(pipeline?["embedding"]);
            var completion = DescribeProvider(pipeline?["completion"]);
            Console.WriteLine(
                $"- {pipeline?["name"]}: embedding {embedding}, completion {completion}");
        }
    }
    return status == "healthy";
}
// --8<-- [end:health]

// --8<-- [start:pipelines]
// Lists the pipelines that the server offers, with their descriptions.
static async Task ListPipelinesAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/pipelines");
    if (reply["pipelines"] is not JsonArray pipelines)
    {
        throw new RagException("Unexpected response: missing pipelines");
    }

    Console.WriteLine($"Pipelines ({pipelines.Count}):");
    foreach (var pipeline in pipelines)
    {
        var description = pipeline?["description"]?.ToString();
        if (string.IsNullOrEmpty(description))
        {
            description = "(no description)";
        }
        Console.WriteLine($"- {pipeline?["name"]}: {description}");
    }
}
// --8<-- [end:pipelines]

// --8<-- [start:main]
bool healthy;
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    await CheckLiveAsync(client);
    healthy = await CheckHealthAsync(client);
    await ListPipelinesAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or RagException)
{
    Console.Error.WriteLine($"RAG Server error: {e.Message}");
    return 1;
}

// A degraded server still answers with HTTP 200, so report it with the
// exit status.
if (!healthy)
{
    Console.Error.WriteLine("RAG Server is not healthy");
    return 1;
}
return 0;

// C# requires type declarations to follow the top-level statements, so
// the exception that the program throws for an error reply is declared
// here, at the end.
class RagException(string message) : Exception(message);
// --8<-- [end:main]
