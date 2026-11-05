/*
 * Ellie's Postgres Cookbook
 * Filtering the documents that the pgEdge RAG Server retrieves, using
 * HttpClient and System.Text.Json.
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

const string Question = "How long does the Acme Widget take to charge?";

// The product to search, and the versions to ask about in turn. The
// question names no version, so only the filter tells the pipeline which
// documents to use.
const string Product = "Acme Widget";
string[] versions = ["1.0", "2.0"];

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const int TimeoutSeconds = 300;
// --8<-- [end:config]

// --8<-- [start:filter]
// Returns the filter for a product and a version. The conditions are
// joined with AND, which is the default, and each one compares a column of
// the pipeline's table with a value. The server passes the values to
// PostgreSQL as parameters, so they need no escaping.
static JsonObject BuildFilter(string product, string version) => new()
{
    ["logic"] = "AND",
    ["conditions"] = new JsonArray(
        new JsonObject
        {
            ["column"] = "product", ["operator"] = "=", ["value"] = product,
        },
        new JsonObject
        {
            ["column"] = "version", ["operator"] = "=", ["value"] = version,
        }),
};
// --8<-- [end:filter]

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

// Sends the question and the filter to the pipeline, and asks for the
// documents that the answer came from. Returns the decoded reply.
static async Task<JsonNode> AskAsync(
    HttpClient client, string question, JsonObject filter)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    var payload = new JsonObject
    {
        ["query"] = question,
        ["filter"] = filter,
        ["include_sources"] = true,
    };
    using var response = await client.PostAsync(url, JsonContent.Create(payload));
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

// --8<-- [start:show]
// Prints the answer in a reply, and then the IDs of its sources.
static void Show(JsonNode reply)
{
    // The sources are missing, rather than an empty list, when there are
    // none, so treat anything other than an array as no sources.
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
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    Console.WriteLine($"Question: {Question}");
    foreach (var version in versions)
    {
        var reply = await AskAsync(client, Question, BuildFilter(Product, version));
        Console.WriteLine();
        Console.WriteLine($"Filter: product = {Product}, version = {version}");
        Show(reply);
    }
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
