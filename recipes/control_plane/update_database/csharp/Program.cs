/*
 * Ellie's Postgres Cookbook
 * Changing a Postgres setting of a pgEdge Control Plane database, checking
 * it from a connection, and putting the original settings back, using
 * HttpClient, System.Text.Json and Npgsql.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The program restores the original settings on every path: after a
 * success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Diagnostics;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
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

static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;

// The password has no default; the Control Plane never returns it, so it
// comes from whoever created the database user.
static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);

const int TimeoutSeconds = 30;

// The setting to change, and its new value.
const string Setting = "work_mem";
const string Value = "16MB";

// How long to wait for an update to finish, and how often to check.
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

// --8<-- [start:update]
// Sends a whole database spec as an update, and returns the ID of the task
// that applies it. The Control Plane compares the spec with the current
// one and changes only what differs; the work happens in the task after
// the reply. The spec is kept as a JSON tree, so that the update sends back
// every field that the server returned.
static async Task<string> UpdateDatabaseAsync(
    HttpClient client, JsonObject spec, CancellationToken token)
{
    var body = new JsonObject { ["spec"] = spec.DeepClone() };
    var reply = await CallAsync(
        client, HttpMethod.Post, $"/v1/databases/{DatabaseId()}", body, token);
    return reply["task"]?["task_id"]?.ToString()
        ?? throw new ControlPlaneException("Unexpected response: missing task_id");
}

// Returns a copy of the spec with the setting changed. postgresql_conf
// holds the Postgres settings that the Control Plane manages, and may be
// missing.
static JsonObject ChangedSpec(JsonObject spec)
{
    var changed = spec.DeepClone().AsObject();
    if (changed["postgresql_conf"] is not JsonObject conf)
    {
        conf = new JsonObject();
        changed["postgresql_conf"] = conf;
    }
    conf[Setting] = Value;
    return changed;
}
// --8<-- [end:update]

// --8<-- [start:wait]
// Polls a task until it finishes, and throws an exception unless it
// completed.
static async Task WaitForTaskAsync(HttpClient client, string taskId, CancellationToken token)
{
    var clock = Stopwatch.StartNew();
    while (clock.Elapsed.TotalSeconds < WaitSeconds)
    {
        var task = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}/tasks/{taskId}", null, token);
        var status = task["status"]?.ToString();
        if (status == "completed")
        {
            return;
        }
        if (status is "failed" or "canceled")
        {
            throw new ControlPlaneException($"the task finished with the status {status}");
        }
        await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
    }
    throw new ControlPlaneException($"the task was still running after {WaitSeconds} seconds");
}
// --8<-- [end:wait]

// --8<-- [start:connect]
// Connects to the first available instance and returns the current value
// of the setting. Each instance runs one node, and its connection_info
// holds the address and port that clients use.
static async Task<string> ShowSettingAsync(HttpClient client, CancellationToken token)
{
    var database = await CallAsync(
        client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, token);
    var info = (database["instances"] as JsonArray ?? [])
        .FirstOrDefault(i => i?["state"]?.ToString() == "available"
            && i["connection_info"]?["addresses"] is JsonArray { Count: > 0 })
        ?["connection_info"]
        ?? throw new ControlPlaneException($"no available instance of {DatabaseId()}");

    // The builder takes care of quoting any special characters.
    var connectionString = new NpgsqlConnectionStringBuilder
    {
        Host = info["addresses"]![0]!.ToString(),
        Port = info["port"]!.GetValue<int>(),
        Database = database["spec"]?["database_name"]?.ToString(),
        Username = DatabaseUser(),
        Password = DatabasePassword(),
        Timeout = TimeoutSeconds,
    }.ConnectionString;

    // await using closes the connection and command when the block exits,
    // whether or not the query failed.
    await using var conn = new NpgsqlConnection(connectionString);
    await conn.OpenAsync(token);
    await using var cmd = new NpgsqlCommand("SELECT current_setting($1)", conn);
    cmd.Parameters.Add(new NpgsqlParameter { Value = Setting });
    return (string)(await cmd.ExecuteScalarAsync(token))!;
}
// --8<-- [end:connect]

// --8<-- [start:restore]
// Sends the original spec back and waits for the task. The Control Plane
// answers 409 whilst another task, such as the update, is still running on
// the database, so the program repeats the request, as it does when no
// reply arrived or the server failed. TaskCanceledException is a timeout
// here, because the cleanup runs after Ctrl-C and so passes no token that
// can be cancelled.
static async Task RestoreAsync(HttpClient client, JsonObject original)
{
    var clock = Stopwatch.StartNew();
    string taskId;
    while (true)
    {
        try
        {
            taskId = await UpdateDatabaseAsync(client, original, CancellationToken.None);
            break;
        }
        catch (Exception e) when (
            e is ControlPlaneException { Status: 409 or >= 500 }
                or HttpRequestException or TaskCanceledException
            && clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
    }
    await WaitForTaskAsync(client, taskId, CancellationToken.None);
}
// --8<-- [end:restore]

// --8<-- [start:main]
if (DatabasePassword() is null)
{
    Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
    return 1;
}

// Ctrl-C and SIGTERM cancel the token below instead of ending the process,
// which lets the program restore the settings before it exits. The
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
var changed = false;
JsonObject original = [];
try
{
    // The spec that the API returns leaves out the passwords of the
    // database users, and an update may leave them out too, which keeps
    // them unchanged.
    var database = await CallAsync(
        client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, interrupt.Token);
    original = database["spec"] as JsonObject
        ?? throw new ControlPlaneException("Unexpected response: missing spec");

    // Restore unless the server refused the request with a 4xx status,
    // which means that it changed nothing.
    Console.WriteLine($"Setting {Setting} to {Value}");
    changed = true;
    string taskId;
    try
    {
        taskId = await UpdateDatabaseAsync(client, ChangedSpec(original), interrupt.Token);
    }
    catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
    {
        changed = false;
        throw;
    }
    await WaitForTaskAsync(client, taskId, interrupt.Token);
    Console.WriteLine("Update completed");

    Console.WriteLine($"{Setting} is now {await ShowSettingAsync(client, interrupt.Token)}");
}
catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
{
    Console.Error.WriteLine("Interrupted");
    exitCode = 130;
}
// NpgsqlException is the base class for the driver's errors, including a
// failure to connect.
catch (NpgsqlException e)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    exitCode = 1;
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
    // Restore the original settings whether the example succeeded, failed,
    // or was interrupted.
    if (changed)
    {
        try
        {
            await RestoreAsync(client, original);
            Console.WriteLine("Restored the original settings");
        }
        catch (Exception e) when (
            e is HttpRequestException or TaskCanceledException or ControlPlaneException)
        {
            Console.Error.WriteLine($"Control Plane error: {e.Message}");
            Console.Error.WriteLine($"Restore the settings of the database {DatabaseId()} by hand");
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
