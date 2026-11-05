/*
 * Ellie's Postgres Cookbook
 * Handling errors from the pgEdge RAG Server, using HttpClient and
 * System.Text.Json.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net.Http.Json;
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
static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");

// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
const string MissingPipeline = "no-such-pipeline";

// The server rejects both requests before it calls a language model, so
// they answer quickly.
const int TimeoutSeconds = 30;
// --8<-- [end:config]

// --8<-- [start:request]
// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Sends a query to a pipeline, and returns the decoded reply. Throws
// ApiException when the server replies with an error.
static async Task<JsonNode?> SendQueryAsync(
    HttpClient client, string pipeline, string query)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(pipeline)}";
    using var response = await client.PostAsync(
        url, JsonContent.Create(new { query }));
    var body = await response.Content.ReadAsStringAsync();
    var status = (int)response.StatusCode;

    JsonNode? reply;
    try
    {
        reply = JsonNode.Parse(body);
    }
    catch (JsonException)
    {
        throw new RagException($"HTTP {status}, {Shorten(body)}");
    }

    if (!response.IsSuccessStatusCode)
    {
        if (reply?["error"] is JsonObject error &&
            error["code"] is JsonValue codeNode &&
            codeNode.TryGetValue(out string? code) &&
            error["message"] is JsonValue messageNode &&
            messageNode.TryGetValue(out string? message))
        {
            throw new ApiException(status, code, message);
        }
        throw new RagException($"HTTP {status}, {Shorten(body)}");
    }
    return reply;
}
// --8<-- [end:request]

// --8<-- [start:advise]
// Returns advice for an error, chosen by the error code. Branch on the code
// rather than on the message, which is meant for people and may change;
// branch on the HTTP status only for the temporary failures that have no
// code worth handling individually.
static string Advise(ApiException err) => err switch
{
    { Code: "PIPELINE_NOT_FOUND" } =>
        "Check the pipeline name; GET /v1/pipelines lists the pipelines.",
    { Code: "INVALID_REQUEST" } =>
        "Fix the request; the body must be JSON with a non-empty query.",
    { Status: 503 or 504 } =>
        "The failure may be temporary, so retry the request later.",
    _ => $"This program does not handle {err.Code}.",
};
// --8<-- [end:advise]

// --8<-- [start:main]
// Sends one query that the server must refuse with the expected error
// code, and prints how the program handles the refusal. Any other outcome
// is a failure.
static async Task DemonstrateAsync(HttpClient client, string title,
    string pipeline, string query, string expected)
{
    Console.WriteLine(title);
    try
    {
        await SendQueryAsync(client, pipeline, query);
    }
    catch (ApiException e)
    {
        Console.WriteLine($"  {e.Code} (HTTP {e.Status}): {e.Detail}");
        Console.WriteLine($"  {Advise(e)}");
        if (e.Code != expected)
        {
            throw new RagException($"expected {expected}, got {e.Code}");
        }
        return;
    }
    throw new RagException("the request unexpectedly succeeded");
}

try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    await DemonstrateAsync(client, "Asking a pipeline that does not exist",
        MissingPipeline, "Hello", "PIPELINE_NOT_FOUND");
    await DemonstrateAsync(client, "Asking an empty question",
        Pipeline(), "", "INVALID_REQUEST");
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or RagException)
{
    Console.Error.WriteLine($"RAG Server error: {e.Message}");
    return 1;
}

return 0;

// C# requires type declarations to follow the top-level statements, so
// the exceptions that the program throws are declared here, at the end.
// RagException is for a reply that the program cannot interpret, and
// ApiException is for an error reply, which has an HTTP status and a JSON
// body of the form {"error": {"code": "...", "message": "..."}}.
class RagException(string message) : Exception(message);

class ApiException(int status, string code, string detail)
    : Exception($"{code}: {detail}")
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public string Detail { get; } = detail;
}
// --8<-- [end:main]
