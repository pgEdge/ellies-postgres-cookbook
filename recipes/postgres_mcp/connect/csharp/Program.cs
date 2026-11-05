/*
 * Ellie's Postgres Cookbook
 * Connecting to the pgEdge Postgres MCP Server, using HttpClient and
 * System.Text.Json.
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

// Posts a JSON-RPC message to the MCP endpoint with a token, and returns
// the HTTP status and the body of the reply.
static async Task<(HttpStatusCode Status, string Body)> PostAsync(
    HttpClient client, string token, JsonObject message)
{
    using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
    {
        Content = new StringContent(
            message.ToJsonString(), Encoding.UTF8, "application/json"),
    };
    request.Headers.Add("Authorization", $"Bearer {token}");
    using var response = await client.SendAsync(request);
    return (response.StatusCode, await response.Content.ReadAsStringAsync());
}

// Sends a JSON-RPC request and returns its result. The server answers a
// JSON-RPC error with HTTP status 200, so the function checks the reply for
// an error member as well as the HTTP status.
static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
{
    var (status, body) = await PostAsync(client, Token(), new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = method,
        ["params"] = parameters,
    });
    if (status != HttpStatusCode.OK)
    {
        throw new McpException(
            $"{method} failed with HTTP {(int)status}: {Shorten(body)}");
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

// --8<-- [start:health]
// Checks that the server is running. The /health endpoint needs no token.
static async Task CheckHealthAsync(HttpClient client)
{
    using var response = await client.GetAsync(BaseUrl() + "/health");
    var body = await response.Content.ReadAsStringAsync();
    if (response.StatusCode != HttpStatusCode.OK)
    {
        throw new McpException(
            $"Health check failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
    }
    if (ParseObject(body)?["status"] is not JsonValue status ||
        status.ToString() != "ok")
    {
        throw new McpException($"Unexpected response: {Shorten(body)}");
    }
    Console.WriteLine("Health: ok");
}
// --8<-- [end:health]

// --8<-- [start:initialize]
// Introduces the client to the server, and prints the server's name and
// version and the protocol revision that the server chose. The server
// accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
// revision it does not know with one that it does, so the client checks
// the answer. The notifications/initialized message then completes the
// handshake; it is a notification, with no id, so the server replies with
// HTTP 202 and no body.
static async Task InitializeAsync(HttpClient client)
{
    var result = await RpcAsync(client, "initialize", new JsonObject
    {
        ["protocolVersion"] = "2025-06-18",
        ["capabilities"] = new JsonObject(),
        ["clientInfo"] = new JsonObject { ["name"] = "cookbook", ["version"] = "1.0.0" },
    });
    if (result["serverInfo"]?["name"] is not JsonValue name ||
        result["serverInfo"]?["version"] is not JsonValue version)
    {
        throw new McpException($"Unexpected result: {result.ToJsonString()}");
    }
    Console.WriteLine($"Server: {name} {version}");
    var protocol = result["protocolVersion"]?.ToString();
    if (protocol != "2025-06-18")
    {
        throw new McpException($"The server chose protocol version {protocol}");
    }
    Console.WriteLine($"Protocol version: {protocol}");

    var (status, body) = await PostAsync(client, Token(), new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["method"] = "notifications/initialized",
    });
    if (status != HttpStatusCode.Accepted)
    {
        throw new McpException(
            $"notifications/initialized failed with HTTP {(int)status}: {Shorten(body)}");
    }
}
// --8<-- [end:initialize]

// --8<-- [start:wrong_token]
// Sends a request with a token that the server does not know, and prints
// the HTTP status and the server's message, which is a JSON object with an
// error member rather than a JSON-RPC reply.
static async Task WrongTokenAsync(HttpClient client)
{
    var (status, body) = await PostAsync(client, "not-a-real-token", new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = "tools/list",
        ["params"] = new JsonObject(),
    });
    if (status != HttpStatusCode.Unauthorized)
    {
        throw new McpException(
            $"Expected HTTP 401 for a wrong token, but got {(int)status}");
    }
    var message = ParseObject(body)?["error"]?.ToString();
    if (string.IsNullOrEmpty(message))
    {
        message = "no message";
    }
    Console.WriteLine($"Wrong token: HTTP {(int)status}, {message}");
}
// --8<-- [end:wrong_token]

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
    await CheckHealthAsync(client);
    await InitializeAsync(client);
    await WrongTokenAsync(client);
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
