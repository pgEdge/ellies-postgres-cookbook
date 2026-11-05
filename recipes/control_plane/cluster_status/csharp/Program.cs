/*
 * Ellie's Postgres Cookbook
 * Checking the version of the pgEdge Control Plane, its cluster, and the
 * state of each host, using HttpClient and System.Text.Json.
 *
 * These examples are for the Control Plane v0.11.0.
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
    EnvOr("CONTROL_PLANE_URL", "http://localhost:3000").TrimEnd('/');

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

// --8<-- [start:version]
// Prints the version of the Control Plane server.
static async Task ShowVersionAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/version");
    if (reply["version"] is not JsonValue node ||
        !node.TryGetValue(out string? version))
    {
        throw new ControlPlaneException("Unexpected response: missing version");
    }
    Console.WriteLine($"Version: {version}");
}
// --8<-- [end:version]

// --8<-- [start:cluster]
// Prints the state of the cluster. A server answers this request only once
// its cluster has been initialised, and it then reports "available"; the
// health of the cluster shows in the state of each host.
static async Task ShowClusterAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/cluster");
    if (reply["status"]?["state"] is not JsonValue node ||
        !node.TryGetValue(out string? state))
    {
        throw new ControlPlaneException("Unexpected response: missing state");
    }
    Console.WriteLine($"Cluster: {state}");
}
// --8<-- [end:cluster]

// --8<-- [start:hosts]
// Lists the hosts in the cluster with their states, and returns whether
// every host is "healthy". The other states are "degraded", "unreachable"
// and "unknown".
static async Task<bool> ShowHostsAsync(HttpClient client)
{
    var reply = await GetAsync(client, "/v1/hosts");
    if (reply["hosts"] is not JsonArray hosts)
    {
        throw new ControlPlaneException("Unexpected response: missing hosts");
    }

    Console.WriteLine($"Hosts ({hosts.Count}):");
    var healthy = true;
    foreach (var host in hosts)
    {
        var state = host?["status"]?["state"]?.ToString() ?? "unknown";
        Console.WriteLine($"- {host?["id"]}: {state}");
        healthy = healthy && state == "healthy";
    }
    return healthy;
}
// --8<-- [end:hosts]

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
    await ShowVersionAsync(client);
    await ShowClusterAsync(client);
    healthy = await ShowHostsAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or ControlPlaneException)
{
    Console.Error.WriteLine($"Control Plane error: {e.Message}");
    return 1;
}

// Report an unhealthy host with the exit status.
if (!healthy)
{
    Console.Error.WriteLine("A host is not healthy");
    return 1;
}
return 0;

// C# requires type declarations to follow the top-level statements, so
// the exception that the program throws for an error reply is declared
// here, at the end.
class ControlPlaneException(string message) : Exception(message);
// --8<-- [end:main]
