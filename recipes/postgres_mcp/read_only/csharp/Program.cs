/*
 * Ellie's Postgres Cookbook
 * Running read-only queries through the pgEdge Postgres MCP Server, using
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

const int TimeoutSeconds = 30;

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

// Calls a tool with tools/call and returns the text of its reply and
// whether the tool failed, which it reports by setting isError. The server
// answers a JSON-RPC error with HTTP status 200, so the function checks the
// reply for an error member as well as the HTTP status.
static async Task<(string Text, bool Failed)> CallToolAsync(
    HttpClient client, string name, JsonObject arguments)
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
    var failed = result["isError"] is JsonValue isError &&
        isError.TryGetValue(out bool flag) && flag;
    return (text, failed);
}
// --8<-- [end:config]

// --8<-- [start:select]
// Runs a SELECT with query_database, and prints the column names and each
// row. The reply repeats the query, with the LIMIT that the server adds,
// and then has a line such as "Results (3 rows):", a header line, and one
// line for each row, with the values separated by tabs. The server writes
// a tab or a newline inside a value as \t or \n, and a NULL as an empty
// string.
static async Task SelectCheapProductsAsync(HttpClient client)
{
    var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
    {
        ["query"] = "SELECT name, price FROM cookbook_mcp.products "
            + "WHERE price < 100 ORDER BY price",
    });
    if (failed)
    {
        throw new McpException($"query_database failed: {text}");
    }
    var lines = text.Split('\n');
    var start = Array.FindIndex(lines, line => line.StartsWith("Results "));
    if (start < 0 || start + 1 >= lines.Length)
    {
        throw new McpException($"Unexpected reply: {Shorten(text)}");
    }
    Console.WriteLine($"Columns: {lines[start + 1].Replace("\t", ", ")}");
    foreach (var line in lines.Skip(start + 2).Where(line => line.Length > 0))
    {
        Console.WriteLine($"Row: {line.Replace("\t", ", ")}");
    }
}
// --8<-- [end:select]

// --8<-- [start:insert]
// Tries to add a row. query_database runs every query in a read-only
// transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
// 25006, and the tool returns the error with isError set to true. The
// INSERT leaves out id, which the table requires, so that even a server
// that allows writes would refuse it rather than save a row. That is
// why the function checks for the read-only error itself rather than
// for any error, and fails if the write succeeds or fails for another
// reason. It prints only the last line of the error, which holds
// PostgreSQL's message, because some errors start with the query.
static async Task TryInsertAsync(HttpClient client)
{
    var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
    {
        ["query"] = "INSERT INTO cookbook_mcp.products "
            + "(name, category, price, in_stock, description) "
            + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
            + "'A made-up product that is never saved')",
    });
    var errorLine = text.Trim().Split('\n')[^1];
    if (!failed)
    {
        throw new McpException("The server accepted a write");
    }
    if (!text.Contains("SQLSTATE 25006"))
    {
        throw new McpException($"The INSERT failed for another reason: {errorLine}");
    }
    Console.WriteLine($"INSERT rejected: {errorLine}");
}
// --8<-- [end:insert]

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
    await SelectCheapProductsAsync(client);
    await TryInsertAsync(client);
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
