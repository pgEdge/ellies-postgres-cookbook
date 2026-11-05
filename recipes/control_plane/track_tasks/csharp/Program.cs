/*
 * Ellie's Postgres Cookbook
 * Finding the task that created a pgEdge Control Plane database, and
 * following its log until the task finishes, using HttpClient and
 * System.Text.Json.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Diagnostics;
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

static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook");

const int TimeoutSeconds = 30;

// How long to follow a task that is still running, and how often to check.
const int FollowSeconds = 600;
const int PollSeconds = 5;

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

// --8<-- [start:list]
// Returns the ID of the task that created the database. Every create,
// update and delete runs as a task. The IDs sort by creation time, and
// sort_order=asc lists the oldest task first.
static async Task<string> FindCreateTaskAsync(HttpClient client)
{
    var reply = await GetAsync(
        client, $"/v1/databases/{DatabaseId()}/tasks?sort_order=asc");
    foreach (var task in reply["tasks"] as JsonArray ?? [])
    {
        if (task?["type"]?.ToString() == "create" &&
            task["task_id"]?.ToString() is { } taskId)
        {
            return taskId;
        }
    }
    throw new ControlPlaneException($"no create task for {DatabaseId()}");
}
// --8<-- [end:list]

// --8<-- [start:follow]
// Prints the log of a task as it grows, until the task finishes, and
// returns its final status. Each log reply carries last_entry_id, and
// passing that back as after_entry_id fetches only the newer entries. The
// status is read before the log, so that once it is final, the log that
// follows it is complete.
static async Task<string> FollowTaskAsync(HttpClient client, string taskId)
{
    string[] finalStatuses = ["completed", "failed", "canceled"];
    var path = $"/v1/databases/{DatabaseId()}/tasks/{taskId}";
    var clock = Stopwatch.StartNew();
    var after = "";
    while (true)
    {
        var task = await GetAsync(client, path);
        var status = task["status"]?.ToString() ?? "unknown";

        var query = after == "" ? "" : $"?after_entry_id={Uri.EscapeDataString(after)}";
        var log = await GetAsync(client, $"{path}/log{query}");
        foreach (var entry in log["entries"] as JsonArray ?? [])
        {
            Console.WriteLine($"Log: {entry?["message"]}");
        }
        if (log["last_entry_id"]?.ToString() is { Length: > 0 } last)
        {
            after = last;
        }

        if (finalStatuses.Contains(status))
        {
            return status;
        }
        if (clock.Elapsed.TotalSeconds >= FollowSeconds)
        {
            throw new ControlPlaneException(
                $"task {taskId} was still {status} after {FollowSeconds} seconds");
        }
        await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
    }
}
// --8<-- [end:follow]

// --8<-- [start:main]
string status;
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    var taskId = await FindCreateTaskAsync(client);
    Console.WriteLine("Task: create");
    status = await FollowTaskAsync(client, taskId);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or ControlPlaneException)
{
    Console.Error.WriteLine($"Control Plane error: {e.Message}");
    return 1;
}

Console.WriteLine($"Status: {status}");
return status == "completed" ? 0 : 1;

// C# requires type declarations to follow the top-level statements, so
// the exception that the program throws for an error reply is declared
// here, at the end.
class ControlPlaneException(string message) : Exception(message);
// --8<-- [end:main]
