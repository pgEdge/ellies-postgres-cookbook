/*
 * Ellie's Postgres Cookbook
 * Asking the pgEdge RAG Server a question, using HttpClient and
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

const string Question = "How long does the Acme Widget 2.0 take to charge?";

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const int TimeoutSeconds = 300;
// --8<-- [end:config]

// --8<-- [start:ask]
// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Describes an error response, which carries a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
static string ErrorText(string body)
{
    try
    {
        if (JsonNode.Parse(body)?["error"] is JsonObject error &&
            error["code"] is JsonValue codeNode &&
            codeNode.TryGetValue(out string? code))
        {
            return $"{code}: {error["message"]}";
        }
    }
    catch (JsonException)
    {
        // The body is not JSON, so show it as it is.
    }
    return Shorten(body.Trim());
}

// Sends the question to the pipeline, and returns the answer with the
// number of tokens the request used.
static async Task<(string Answer, long TokensUsed)> AskAsync(
    HttpClient client, string question)
{
    // EscapeDataString escapes any character in the pipeline name that is
    // not safe in a URL path. JsonContent serialises the request body,
    // which escapes the question correctly.
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    using var response = await client.PostAsync(
        url, JsonContent.Create(new { query = question }));
    var body = await response.Content.ReadAsStringAsync();

    // HttpClient treats an error status as a normal response, so check it
    // here.
    if (!response.IsSuccessStatusCode)
    {
        throw new RagException(
            $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
    }

    try
    {
        // TryGetValue fails when a field holds a different type, such as
        // a number where the answer should be.
        var reply = JsonNode.Parse(body);
        if (reply?["answer"] is JsonValue answerNode &&
            answerNode.TryGetValue(out string? answer) &&
            reply["tokens_used"] is JsonValue tokensNode &&
            tokensNode.TryGetValue(out long tokensUsed))
        {
            return (answer, tokensUsed);
        }
    }
    catch (JsonException)
    {
        // The body is not JSON; report it below.
    }
    throw new RagException($"Unexpected response: {Shorten(body)}");
}
// --8<-- [end:ask]

// --8<-- [start:main]
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    var (answer, tokensUsed) = await AskAsync(client, Question);

    Console.WriteLine($"Question: {Question}");
    Console.WriteLine($"Answer:\n{answer}");
    Console.WriteLine($"Tokens used: {tokensUsed}");
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
// the exception that the program throws for an error reply is declared
// here, at the end.
class RagException(string message) : Exception(message);
// --8<-- [end:main]
