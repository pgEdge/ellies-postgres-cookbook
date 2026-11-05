/*
 * Ellie's Postgres Cookbook
 * Reading resources and prompts from the pgEdge Postgres MCP Server, using
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

// Sends a JSON-RPC request and returns its result. The server answers a
// JSON-RPC error with HTTP status 200, so the function checks the reply for
// an error member as well as the HTTP status.
static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
{
    var message = new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = method,
        ["params"] = parameters,
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
            $"{method} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
    }
    var reply = ParseObject(body);
    if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
    {
        throw new McpException($"{method} failed: unexpected response: {Shorten(body)}");
    }
    if (reply.ContainsKey("error"))
    {
        throw new McpException($"{method} failed: {reply["error"]?["message"]}");
    }
    return reply["result"] ?? throw new McpException($"{method} failed: no result");
}
// --8<-- [end:config]

// --8<-- [start:resources]
// Lists the resources that the server offers, and then reads
// pg://system_info, which describes the PostgreSQL server. The contents of
// a resource are text, which for this one holds a JSON object, so the
// function parses the text a second time. version_number is a string such
// as "180006", from which integer division by 10000 gives the major
// version.
static async Task ReadSystemInfoAsync(HttpClient client)
{
    var list = await RpcAsync(client, "resources/list", new JsonObject());
    var uris = list["resources"]?.AsArray().Select(r => r?["uri"]?.ToString()) ?? [];
    Console.WriteLine($"Resources: {string.Join(", ", uris)}");

    var result = await RpcAsync(client, "resources/read", new JsonObject
    {
        ["uri"] = "pg://system_info",
    });
    var info = ParseObject(result["contents"]?[0]?["text"]?.ToString() ?? "");
    if (info?["allow_writes"] is not JsonValue allowWrites ||
        !allowWrites.TryGetValue(out bool writes) ||
        !int.TryParse(info["version_number"]?.ToString(), out var versionNumber))
    {
        throw new McpException($"Unexpected result: {Shorten(result.ToJsonString())}");
    }
    Console.WriteLine($"PostgreSQL major version: {versionNumber / 10000}");
    // bool.ToString() gives "True" or "False", so the program writes the
    // JSON spelling instead.
    Console.WriteLine($"Writes allowed: {(writes ? "true" : "false")}");
}
// --8<-- [end:resources]

// --8<-- [start:prompts]
// Lists the prompts that the server offers, and then fetches
// explore-database, which takes no arguments. A prompt is a set of
// messages, ready to hand to a language model, that guide it through a
// task with the server's tools.
static async Task ReadPromptsAsync(HttpClient client)
{
    var list = await RpcAsync(client, "prompts/list", new JsonObject());
    var names = list["prompts"]?.AsArray().Select(p => p?["name"]?.ToString()) ?? [];
    Console.WriteLine($"Prompts: {string.Join(", ", names)}");

    var prompt = await RpcAsync(client, "prompts/get", new JsonObject
    {
        ["name"] = "explore-database",
        ["arguments"] = new JsonObject(),
    });
    if (prompt["messages"]?[0]?["role"] is not JsonValue role)
    {
        throw new McpException($"Unexpected result: {Shorten(prompt.ToJsonString())}");
    }
    Console.WriteLine($"explore-database: {prompt["description"]}");
    Console.WriteLine($"First message role: {role}");
}
// --8<-- [end:prompts]

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
    await ReadSystemInfoAsync(client);
    await ReadPromptsAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
// InvalidOperationException covers a member of the reply that has the
// wrong type, such as a list that is not an array.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or McpException
        or InvalidOperationException)
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
