/*
 * Ellie's Postgres Cookbook
 * Showing the documents behind a pgEdge RAG Server answer, using
 * HttpClient and System.Text.Json.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net.Http.Json;
using System.Text;
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

// Sends the question to the pipeline, and asks for the documents that the
// answer came from as well. Returns the decoded reply.
static async Task<JsonNode> AskAsync(HttpClient client, string question)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    using var response = await client.PostAsync(
        url, JsonContent.Create(new { query = question, include_sources = true }));
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
        var reply = JsonNode.Parse(body);
        if (reply?["answer"] is JsonValue answerNode &&
            answerNode.TryGetValue(out string? _))
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
// --8<-- [end:ask]

// --8<-- [start:sources]
// Returns one line for a source: its ID and the start of its text.
static string DescribeSource(JsonNode? source)
{
    // Collapse any line breaks, and shorten long text for display. The
    // length counts characters (runes) rather than the UTF-16 units that
    // Length counts.
    var words = (source?["content"]?.ToString() ?? "")
        .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    var content = string.Join(" ", words);
    var runes = content.EnumerateRunes().ToArray();
    if (runes.Length > 60)
    {
        content = string.Concat(runes.Take(57).Select(r => r.ToString())) + "...";
    }
    return $"- {source?["id"]?.ToString() ?? "(no id)"}: {content}";
}

// Prints the sources in a reply, in the order the server returns.
static void PrintSources(JsonNode reply)
{
    // The server leaves out the sources array, without an error, when the
    // pipeline does not set allow_include_sources.
    if (reply["sources"] is not JsonArray { Count: > 0 } sources)
    {
        Console.WriteLine(
            "No sources were returned. Does the pipeline set allow_include_sources?");
        return;
    }

    Console.WriteLine($"Sources ({sources.Count}):");
    foreach (var source in sources)
    {
        Console.WriteLine(DescribeSource(source));
    }
}
// --8<-- [end:sources]

// --8<-- [start:main]
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    var reply = await AskAsync(client, Question);

    Console.WriteLine($"Question: {Question}");
    Console.WriteLine($"Answer:\n{reply["answer"]}");
    PrintSources(reply);
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
