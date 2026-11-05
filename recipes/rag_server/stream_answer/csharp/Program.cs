/*
 * Ellie's Postgres Cookbook
 * Streaming an answer from the pgEdge RAG Server, using HttpClient and
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

// The server may wait for the language model before it starts to answer,
// and a small model on a modest machine can take a while, so allow plenty
// of time.
const int TimeoutSeconds = 300;
// --8<-- [end:config]

// --8<-- [start:events]
// Parses Server-Sent Events from a reader, and yields the JSON that the
// data of each event holds, as each event arrives.
//
// An event is one or more "data:" lines followed by a blank line. The
// stream may end without the final blank line, so the last event is sent
// when the lines run out as well. JsonNode.Parse throws a JsonException
// for data that is not valid JSON.
static async IAsyncEnumerable<JsonNode?> ReadEventsAsync(StreamReader reader)
{
    var data = new List<string>();
    while (await reader.ReadLineAsync() is { } line)
    {
        if (line.Length == 0)
        {
            if (data.Count > 0)
            {
                yield return JsonNode.Parse(string.Join("\n", data));
                data.Clear();
            }
        }
        else if (line.StartsWith("data:", StringComparison.Ordinal))
        {
            // A single space after the colon is not part of the data.
            var value = line["data:".Length..];
            data.Add(value.StartsWith(' ') ? value[1..] : value);
        }
        // Comment lines (which start with a colon) and other fields are
        // ignored.
    }
    if (data.Count > 0)
    {
        yield return JsonNode.Parse(string.Join("\n", data));
    }
}
// --8<-- [end:events]

// --8<-- [start:stream]
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
    var text = body.Trim();
    return text.Length > 200 ? text[..200] : text;
}

// Prints the answer as it arrives, and returns the number of chunks.
static async Task<int> StreamAnswerAsync(HttpClient client, string question)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    using var request = new HttpRequestMessage(HttpMethod.Post, url)
    {
        Content = JsonContent.Create(new { query = question, stream = true }),
    };
    // ResponseHeadersRead returns as soon as the headers arrive, rather
    // than after the whole body, so the body can be read as the server
    // sends it.
    using var response = await client.SendAsync(
        request, HttpCompletionOption.ResponseHeadersRead);

    // A request the server rejects gets an ordinary error status. Once
    // streaming starts the status is always 200, so later failures arrive
    // as events instead.
    if (!response.IsSuccessStatusCode)
    {
        var body = await response.Content.ReadAsStringAsync();
        throw new RagException(
            $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
    }

    var chunks = 0;
    string? error = null;
    var done = false;

    using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
    await foreach (var ev in ReadEventsAsync(reader))
    {
        // Anything other than a JSON object is not an event this program
        // knows, so skip it.
        if (ev is not JsonObject obj)
        {
            continue;
        }
        switch (obj["type"]?.ToString())
        {
            case "chunk":
                // The last chunk has no content.
                var content = obj["content"]?.ToString();
                if (!string.IsNullOrEmpty(content))
                {
                    Console.Write(content);
                    chunks++;
                }
                break;
            case "error":
                var message = obj["error"]?.ToString();
                error = string.IsNullOrEmpty(message) ? "unknown error" : message;
                break;
            case "done":
                done = true;
                break;
        }
    }

    Console.WriteLine();
    // The server sends a done event after an error event, so keep reading
    // until the stream ends before reporting the error.
    if (error is not null)
    {
        throw new RagException($"The stream reported an error: {error}");
    }
    if (!done)
    {
        throw new RagException("The stream ended before the done event");
    }
    return chunks;
}
// --8<-- [end:stream]

// --8<-- [start:main]
Console.WriteLine($"Question: {Question}");
Console.WriteLine("Answer:");
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    var chunks = await StreamAnswerAsync(client, Question);
    Console.WriteLine($"Chunks received: {chunks}");
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, TaskCanceledException covers a timeout, IOException
// covers a failure part of the way through the stream, and JsonException
// covers an event whose data is not valid JSON.
catch (Exception e) when (e is HttpRequestException or TaskCanceledException
    or IOException or JsonException or RagException)
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
