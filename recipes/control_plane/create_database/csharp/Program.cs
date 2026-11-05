/*
 * Ellie's Postgres Cookbook
 * Creating a pgEdge Control Plane database on one host, waiting until it
 * is available, and deleting it again, using HttpClient and
 * System.Text.Json.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The database runs in containers on the host until it is deleted, so
 * this program deletes the database it creates on every path: after a
 * success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Diagnostics;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
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

// The new database listens on the given port on its host, so choose one
// that is free.
static int Port() => int.Parse(EnvOr("CONTROL_PLANE_RECIPE_PORT", "6433"));

const int TimeoutSeconds = 30;

// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const int WaitSeconds = 600;
const int PollSeconds = 5;

// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Sends a request to the server, with the body encoded as JSON if it is
// not null, and returns the decoded reply. The token stops the request
// when the user presses Ctrl-C.
static async Task<JsonObject> CallAsync(
    HttpClient client, HttpMethod method, string path, object? body,
    CancellationToken token)
{
    using var request = new HttpRequestMessage(method, BaseUrl() + path);
    if (body is not null)
    {
        request.Content = JsonContent.Create(body);
    }
    using var response = await client.SendAsync(request, token);
    var text = await response.Content.ReadAsStringAsync(token);
    if (!response.IsSuccessStatusCode)
    {
        throw new ControlPlaneException(
            $"HTTP {(int)response.StatusCode}, {Shorten(text)}",
            (int)response.StatusCode);
    }
    try
    {
        if (JsonNode.Parse(text) is JsonObject reply)
        {
            return reply;
        }
    }
    catch (JsonException)
    {
        // The body is not JSON; report it below.
    }
    throw new ControlPlaneException($"Unexpected response: {Shorten(text)}");
}
// --8<-- [end:config]

// --8<-- [start:host]
// Returns the ID of the first host in the cluster. A database places each
// of its nodes on one or more hosts, which run the Postgres containers.
static async Task<string> FirstHostAsync(HttpClient client, CancellationToken token)
{
    var reply = await CallAsync(client, HttpMethod.Get, "/v1/hosts", null, token);
    if (reply["hosts"] is not JsonArray { Count: > 0 } hosts ||
        hosts[0]?["id"]?.ToString() is not { } host)
    {
        throw new ControlPlaneException("the cluster has no hosts");
    }
    return host;
}
// --8<-- [end:host]

// --8<-- [start:create]
// Asks the Control Plane to create a database with one node. The reply
// holds the database and the task that creates it; the work happens in the
// background after the reply.
static async Task CreateDatabaseAsync(
    HttpClient client, string databaseId, string host, CancellationToken token)
{
    var body = new
    {
        id = databaseId,
        spec = new
        {
            database_name = "recipe",
            port = Port(),
            nodes = new[] { new { name = "n1", host_ids = new[] { host } } },
        },
    };
    await CallAsync(client, HttpMethod.Post, "/v1/databases", body, token);
}
// --8<-- [end:create]

// --8<-- [start:wait]
// Polls the database, printing its state each time it changes, until the
// state is available, and returns the port of its first instance. Each
// instance runs one node, and its connection_info holds the address and
// port that clients use. A failed state ends the wait at once.
static async Task<string> WaitUntilAvailableAsync(
    HttpClient client, string databaseId, CancellationToken token)
{
    var clock = Stopwatch.StartNew();
    string? last = null;
    while (clock.Elapsed.TotalSeconds < WaitSeconds)
    {
        var database = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{databaseId}", null, token);
        var state = database["state"]?.ToString();
        if (state != last)
        {
            Console.WriteLine($"Database state: {state}");
            last = state;
        }
        if (state == "available")
        {
            return database["instances"]?[0]?["connection_info"]?["port"]?.ToString() ?? "";
        }
        if (state == "failed")
        {
            throw new ControlPlaneException("the database has the state failed");
        }
        await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
    }
    throw new ControlPlaneException(
        $"the database was not available after {WaitSeconds} seconds");
}
// --8<-- [end:wait]

// --8<-- [start:delete]
// Reports whether a failed request is worth repeating: no reply arrived,
// the server failed, or it answered 409, which the Control Plane does
// whilst another task, such as the create, is still running on the
// database. TaskCanceledException is a timeout here, because the cleanup
// does not pass a token that can be cancelled.
static bool IsTransient(Exception e) => e switch
{
    ControlPlaneException cpe => cpe.Status is 409 or >= 500,
    HttpRequestException or TaskCanceledException => true,
    _ => false,
};

// Deletes the database and waits until the API no longer has it. A 404
// means that the database is already gone. The cleanup runs after Ctrl-C,
// so it uses no cancellation token.
static async Task DeleteDatabaseAsync(HttpClient client, string databaseId)
{
    var path = $"/v1/databases/{databaseId}";
    var clock = Stopwatch.StartNew();
    while (true)
    {
        try
        {
            await CallAsync(client, HttpMethod.Delete, path, null, CancellationToken.None);
            break;
        }
        catch (ControlPlaneException e) when (e.Status == 404)
        {
            return;
        }
        catch (Exception e) when (IsTransient(e) && clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
    }

    // The delete starts a task that removes the database; a 404 shows that
    // it has finished.
    while (clock.Elapsed.TotalSeconds < WaitSeconds)
    {
        try
        {
            await CallAsync(client, HttpMethod.Get, path, null, CancellationToken.None);
        }
        catch (ControlPlaneException e) when (e.Status == 404)
        {
            return;
        }
        catch (Exception e) when (IsTransient(e))
        {
            // Check again after the pause.
        }
        await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
    }
    throw new ControlPlaneException(
        $"the database was still present after {WaitSeconds} seconds");
}
// --8<-- [end:delete]

// --8<-- [start:main]
// Ctrl-C and SIGTERM cancel the token below instead of ending the process,
// which lets the program delete its database before it exits. The
// registrations stay in place, so a further Ctrl-C does not end the
// process during the cleanup either.
using var interrupt = new CancellationTokenSource();
void OnSignal(PosixSignalContext context)
{
    context.Cancel = true;
    interrupt.Cancel();
}
using var sigint = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
using var sigterm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);

// using disposes of the client, and closes its connections, when the
// program ends.
using var client = new HttpClient
{
    Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
};

var exitCode = 0;
var created = false;
// The client chooses the ID of a new database, so the program knows it
// before the request, and can delete the database even if the reply never
// arrives. The random suffix keeps the ID unique.
var databaseId = $"cookbook-recipe-{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3))}";
try
{
    var host = await FirstHostAsync(client, interrupt.Token);
    Console.WriteLine($"Host: {host}");

    // Clean up unless the server refused the request with a 4xx status,
    // which means it created nothing; a 409, for example, means that a
    // database with this ID already exists, and is not this program's to
    // delete.
    created = true;
    try
    {
        await CreateDatabaseAsync(client, databaseId, host, interrupt.Token);
    }
    catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
    {
        created = false;
        throw;
    }
    Console.WriteLine($"Created database {databaseId}");

    var port = await WaitUntilAvailableAsync(client, databaseId, interrupt.Token);
    Console.WriteLine($"Database is available on port {port}");
}
catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
{
    Console.Error.WriteLine("Interrupted");
    exitCode = 130;
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or ControlPlaneException)
{
    Console.Error.WriteLine($"Control Plane error: {e.Message}");
    exitCode = 1;
}
finally
{
    // Delete the database whether the example succeeded, failed, or was
    // interrupted.
    if (created)
    {
        try
        {
            await DeleteDatabaseAsync(client, databaseId);
            Console.WriteLine("Deleted database");
        }
        catch (Exception e) when (
            e is HttpRequestException or TaskCanceledException or ControlPlaneException)
        {
            Console.Error.WriteLine($"Control Plane error: {e.Message}");
            Console.Error.WriteLine($"Delete the database {databaseId} by hand");
            exitCode = 1;
        }
    }
}
return exitCode;

// C# requires type declarations to follow the top-level statements, so
// the exception that the program throws for an error reply is declared
// here, at the end. The status is the HTTP status of the reply, or 0 if
// there was none.
class ControlPlaneException(string message, int status = 0) : Exception(message)
{
    public int Status { get; } = status;
}
// --8<-- [end:main]
