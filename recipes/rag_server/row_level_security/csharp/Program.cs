/*
 * Ellie's Postgres Cookbook
 * Answering each caller from only their own documents with the pgEdge RAG
 * Server and row-level security, using HttpClient and System.Text.Json.
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
static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook_private");

const string Question = "What is the status of my warranty claim?";

// The callers to ask for. The fictional documents in the pipeline's table
// belong to these two people.
string[] callers = ["jane.doe@example.com", "john.smith@example.com"];

// The header in which the server expects a trusted proxy to put the claims
// of the caller. This is the server's default; the identity.claims_header
// setting changes it.
const string ClaimsHeader = "X-Forwarded-Claims";

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const int TimeoutSeconds = 300;
// --8<-- [end:config]

// --8<-- [start:ask]
// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Sends the question to the pipeline on behalf of a caller, and asks for
// the documents that the answer came from. Returns the decoded reply. A
// subject of null sends no identity at all.
static async Task<JsonNode> AskAsync(HttpClient client, string? subject)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    using var request = new HttpRequestMessage(HttpMethod.Post, url)
    {
        Content = JsonContent.Create(new { query = Question, include_sources = true }),
    };
    // The claims are a JSON object, which JsonSerializer builds, so that
    // the subject needs no escaping.
    if (subject is not null)
    {
        request.Headers.Add(ClaimsHeader, JsonSerializer.Serialize(new { sub = subject }));
    }
    using var response = await client.SendAsync(request);
    var body = await response.Content.ReadAsStringAsync();
    var status = (int)response.StatusCode;

    JsonNode? reply = null;
    try
    {
        reply = JsonNode.Parse(body);
    }
    catch (JsonException)
    {
        // The body is not JSON; report it below.
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

    if (reply?["answer"] is JsonValue answerNode &&
        answerNode.TryGetValue(out string? _))
    {
        return reply;
    }
    throw new RagException($"Unexpected response: {Shorten(body)}");
}
// --8<-- [end:ask]

// --8<-- [start:show]
// Prints the answer in a reply, and then the IDs of its sources.
static void Show(JsonNode reply)
{
    var ids = new List<string>();
    if (reply["sources"] is JsonArray sources)
    {
        foreach (var source in sources)
        {
            ids.Add(source?["id"]?.ToString() ?? "(no id)");
        }
    }
    Console.WriteLine($"Answer:\n{reply["answer"]}");
    Console.WriteLine($"Sources: {string.Join(", ", ids)}");
}
// --8<-- [end:show]

// --8<-- [start:main]
// Asks the question without an identity. The server must refuse with
// IDENTITY_REQUIRED, because it never falls back to the pipeline's own
// database role; any other outcome is a failure.
static async Task AskAnonymouslyAsync(HttpClient client)
{
    Console.WriteLine();
    Console.WriteLine("Caller: (no identity)");
    try
    {
        await AskAsync(client, null);
    }
    catch (ApiException e)
    {
        Console.WriteLine($"{e.Code} (HTTP {e.Status})");
        if (e.Code != "IDENTITY_REQUIRED")
        {
            throw new RagException($"expected IDENTITY_REQUIRED, got {e.Message}");
        }
        return;
    }
    throw new RagException(
        "the server answered without an identity; is identity.enabled set?");
}

try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    Console.WriteLine($"Question: {Question}");
    foreach (var caller in callers)
    {
        var reply = await AskAsync(client, caller);
        Console.WriteLine();
        Console.WriteLine($"Caller: {caller}");
        Show(reply);
    }
    await AskAnonymouslyAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (e is HttpRequestException or TaskCanceledException
    or ApiException or RagException)
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
}
// --8<-- [end:main]
