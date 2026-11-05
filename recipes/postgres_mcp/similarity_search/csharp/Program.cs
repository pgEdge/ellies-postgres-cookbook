/*
 * Ellie's Postgres Cookbook
 * Searching by meaning through the pgEdge Postgres MCP Server, using
 * HttpClient and System.Text.Json.
 *
 * These examples are for pgEdge Postgres MCP Server 1.1.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or a fallback if the
// variable is unset or empty.
static string EnvOr(string name, string fallback) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : fallback;

static string BaseUrl() => EnvOr("MCP_URL", "http://localhost:8080").TrimEnd('/');
static string Token() => EnvOr("MCP_TOKEN", "");

// The server turns the query into an embedding before it searches, which
// can take a while if the embedding model has to load first, so the
// timeout is longer than in the other recipes.
const int TimeoutSeconds = 90;

const string Query = "a gift for an amateur astronomer";

// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Parses a reply as a JSON object, or returns null if it is not one.
static JsonObject? ParseObject(string text)
{
    try
    {
        return JsonNode.Parse(text) as JsonObject;
    }
    catch (JsonException)
    {
        return null;
    }
}

// Calls a tool with tools/call and returns the text of its reply. The
// server answers a JSON-RPC error with HTTP status 200, and a tool that
// fails returns a normal result with isError set, so the function checks
// for both as well as the HTTP status.
static async Task<string> CallToolAsync(HttpClient client, string name, JsonObject arguments)
{
    var message = new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = "tools/call",
        ["params"] = new JsonObject { ["name"] = name, ["arguments"] = arguments },
    };
    using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
    {
        Content = new StringContent(
            message.ToJsonString(), Encoding.UTF8, "application/json"),
    };
    request.Headers.Add("Authorization", $"Bearer {Token()}");
    using var response = await client.SendAsync(request);
    var body = await response.Content.ReadAsStringAsync();
    if (response.StatusCode != HttpStatusCode.OK)
    {
        throw new McpException(
            $"{name} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
    }
    var reply = ParseObject(body);
    if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
    {
        throw new McpException($"{name} failed: unexpected response: {Shorten(body)}");
    }
    if (reply.ContainsKey("error"))
    {
        throw new McpException($"{name} failed: {reply["error"]?["message"]}");
    }
    var result = reply["result"];
    if (result?["content"]?[0]?["text"] is not JsonValue textValue ||
        !textValue.TryGetValue(out string? text))
    {
        throw new McpException($"{name} failed: unexpected result: {Shorten(body)}");
    }
    if (result["isError"] is JsonValue isError &&
        isError.TryGetValue(out bool failed) && failed)
    {
        throw new McpException($"{name} failed: {text}");
    }
    return text;
}
// --8<-- [end:config]

// --8<-- [start:search]
// Searches the product descriptions for the query, and prints the number
// of results and the name of the product that matches it most closely.
// similarity_search finds the closest rows by vector distance, and then
// reorders them, mixing in a keyword score and favouring variety, so the
// first result in the reply is not always the closest. Each result has a
// line such as "Source: cookbook_mcp.products.description (vector search
// rank: #1, chunk: 1)"; the function picks the result ranked first by the
// vector search, whose text follows the first blank line after it. Every
// description starts with the product's name and a colon.
static async Task SearchAsync(HttpClient client)
{
    var text = await CallToolAsync(client, "similarity_search", new JsonObject
    {
        ["table_name"] = "cookbook_mcp.products",
        ["query_text"] = Query,
        ["top_n"] = 3,
    });
    Console.WriteLine($"Query: {Query}");
    var lines = text.Split('\n');
    var count = lines.Count(line => Regex.IsMatch(line, @"^Result \d+/\d+$"));
    Console.WriteLine($"Results: {count}");

    var source = Array.FindIndex(lines, line =>
        line.StartsWith("Source: ") &&
        line.EndsWith("(vector search rank: #1, chunk: 1)"));
    var blank = source < 0 ? -1 : Array.FindIndex(lines, source + 1, line => line.Length == 0);
    var best = blank < 0 || blank + 1 >= lines.Length ? "" : lines[blank + 1];
    var colon = best.IndexOf(": ", StringComparison.Ordinal);
    if (colon < 0)
    {
        throw new McpException($"The reply had no closest match: {Shorten(text)}");
    }
    Console.WriteLine($"Best match: {best[..colon]}");
}
// --8<-- [end:search]

// --8<-- [start:main]
if (Token().Length == 0)
{
    Console.Error.WriteLine("MCP_TOKEN must be set");
    return 1;
}
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    await SearchAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or McpException)
{
    Console.Error.WriteLine($"MCP Server error: {e.Message}");
    return 1;
}
return 0;

// C# requires type declarations to follow the top-level statements, so
// the exception that the program throws for an error reply is declared
// here, at the end.
class McpException(string message) : Exception(message);
// --8<-- [end:main]
