/*
 * Ellie's Postgres Cookbook
 * Scheduling a maintenance blackout with the AI DBA Workbench API, using
 * HttpClient and System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or null if the variable
// is unset or empty, as an unset variable would be.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Reads the settings from the environment.
static (string BaseUrl, string Token, long ConnectionId) Settings()
{
    var token = EnvValue("WORKBENCH_TOKEN");
    var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
    if (token is null || connectionId is null)
    {
        throw new InvalidOperationException(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
    }
    if (!connectionId.All(char.IsAsciiDigit))
    {
        throw new InvalidOperationException(
            "WORKBENCH_CONNECTION_ID must be a number");
    }
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    return (baseUrl.TrimEnd('/'), token, long.Parse(connectionId));
}
// --8<-- [end:config]

// --8<-- [start:request]
// The name of the signal that the program received, if any, and a token
// that the signal cancels, which abandons the request in progress.
string? interrupted = null;
using var signalled = new CancellationTokenSource();

// Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
// which would end the program before it could delete the blackout, and a
// second signal does nothing more.
void OnSignal(PosixSignalContext context)
{
    context.Cancel = true;
    interrupted ??= context.Signal.ToString();
    signalled.Cancel();
}
using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);

// One client serves every request, with a timeout for each.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
var cfg = (BaseUrl: "", Token: "", ConnectionId: 0L);

// Sends a request to the API and returns the JSON reply, or null if the
// reply has no body. A request that the server rejects throws an error
// that includes the message from the server. After a signal, every
// request that is interruptible fails at once, and a signal abandons one
// in progress; the cleanup and the create call, whose result the program
// must not lose, pass false.
async Task<JsonNode?> Api(string method, string path, bool interruptible,
    object? body = null)
{
    var cancel = interruptible ? signalled.Token : CancellationToken.None;
    try
    {
        cancel.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", cfg.Token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

        using var response = await http.SendAsync(request, cancel);
        var text = await response.Content.ReadAsStringAsync(cancel);
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return text.Length == 0 ? null : JsonNode.Parse(text);
    }
    catch (OperationCanceledException) when (cancel.IsCancellationRequested)
    {
        throw new InvalidOperationException($"Interrupted by {interrupted}");
    }
}
// --8<-- [end:request]

// --8<-- [start:create]
// Creates a blackout for one monitored server and returns it. The blackout
// starts a minute ago, so that a small difference between the clocks of
// this machine and the server cannot leave it inactive, and it ends in one
// hour. The "O" format writes the times in RFC 3339 format.
async Task<JsonNode> CreateBlackout()
{
    var now = DateTimeOffset.UtcNow;
    return await Api("POST", "/blackouts", false, new
    {
        scope = "server",
        connection_id = cfg.ConnectionId,
        reason = "Cookbook maintenance window",
        start_time = now.AddMinutes(-1).ToString("O"),
        end_time = now.AddHours(1).ToString("O"),
    }) ?? throw new InvalidOperationException("The reply had no blackout");
}
// --8<-- [end:create]

// --8<-- [start:read]
// Returns the blackout with the given ID.
async Task<JsonNode> GetBlackout(long blackoutId) =>
    await Api("GET", $"/blackouts/{blackoutId}", true)
        ?? throw new InvalidOperationException("The reply had no blackout");
// --8<-- [end:read]

// --8<-- [start:stop]
// Stops a blackout that is in progress, which sets its end time to now,
// and returns the stopped blackout.
async Task<JsonNode> StopBlackout(long blackoutId) =>
    await Api("POST", $"/blackouts/{blackoutId}/stop", true)
        ?? throw new InvalidOperationException("The reply had no blackout");
// --8<-- [end:stop]

// --8<-- [start:delete]
// Deletes a blackout by its ID.
async Task DeleteBlackout(long blackoutId) =>
    await Api("DELETE", $"/blackouts/{blackoutId}", false);
// --8<-- [end:delete]

// --8<-- [start:main]
// Reports whether an error is one that the program expects: a failure to
// connect, a reply that the server rejected, a request that timed out or
// was interrupted, or a reply that lacked what we need.
static bool Expected(Exception e) => e is HttpRequestException
    or TaskCanceledException or InvalidOperationException or JsonException;

// Returns the is_active flag of a blackout, as the other languages print
// it; C# would print True or False.
static string Active(JsonNode blackout) =>
    blackout["is_active"]!.GetValue<bool>() ? "true" : "false";

long? blackoutId = null;
var status = 0;
try
{
    cfg = Settings();

    var created = await CreateBlackout();
    blackoutId = created["id"]!.GetValue<long>();
    Console.WriteLine(
        $"Created a blackout for the server (active: {Active(created)})");

    var blackout = await GetBlackout(blackoutId.Value);
    Console.WriteLine($"Read the blackout back (active: {Active(blackout)})");

    var stopped = await StopBlackout(blackoutId.Value);
    Console.WriteLine($"Stopped the blackout (active: {Active(stopped)})");
    if (stopped["is_active"]!.GetValue<bool>())
    {
        throw new InvalidOperationException("The blackout is still active");
    }

    await DeleteBlackout(blackoutId.Value);
    blackoutId = null;
    Console.WriteLine("Deleted the blackout");
}
catch (Exception e) when (Expected(e))
{
    Console.Error.WriteLine($"Error: {e.Message}");
    status = 1;
}
finally
{
    // Delete the blackout whether or not a later step failed, so that a failed
    // run does not leave alerts suppressed. The finally block also runs for an
    // error that the catch does not handle.
    if (blackoutId is long pending)
    {
        try
        {
            await DeleteBlackout(pending);
        }
        catch (Exception e) when (Expected(e))
        {
            Console.Error.WriteLine(
                $"Error: could not delete the blackout: {e.Message}");
            status = 1;
        }
    }
}

return status;
// --8<-- [end:main]
