/*
 * Ellie's Postgres Cookbook
 * Calling AI DBA Workbench MCP tools, using HttpClient and
 * System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or null if the variable
// is unset or empty, as an unset variable would be.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Reads the settings from the environment.
static (string BaseUrl, string Token, long ConnectionId) Settings()
{
    var token = EnvValue("WORKBENCH_TOKEN");
    var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
    if (token is null || connectionId is null)
    {
        throw new InvalidOperationException(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
    }
    if (!Regex.IsMatch(connectionId, "^[0-9]+$"))
    {
        throw new InvalidOperationException(
            "WORKBENCH_CONNECTION_ID must be a number");
    }
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    return (baseUrl.TrimEnd('/'), token, long.Parse(connectionId));
}
// --8<-- [end:config]

// --8<-- [start:rpc]
// One client serves every request, with a timeout for each.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

// Sends a JSON-RPC request to the MCP endpoint and returns the result. The
// server answers a JSON-RPC error with HTTP status 200, so the function
// checks the reply for an error member as well as for an HTTP failure.
async Task<JsonNode> Rpc(string baseUrl, string token, string method,
    object parameters)
{
    using var request = new HttpRequestMessage(HttpMethod.Post,
        $"{baseUrl}/mcp/v1")
    {
        Content = JsonContent.Create(new
        {
            jsonrpc = "2.0",
            id = 1,
            method,
            @params = parameters,
        }),
    };
    request.Headers.Authorization =
        new AuthenticationHeaderValue("Bearer", token);

    using var response = await http.SendAsync(request);
    var text = await response.Content.ReadAsStringAsync();
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"{method} failed with status {(int)response.StatusCode}: "
            + text.Trim());
    }
    var reply = JsonNode.Parse(text)
        ?? throw new InvalidOperationException($"{method} returned no JSON");
    if (reply["error"] is JsonNode error)
    {
        throw new InvalidOperationException(
            $"{method} failed: {error["message"]}");
    }
    return reply["result"]
        ?? throw new InvalidOperationException($"{method} had no result");
}
// --8<-- [end:rpc]

// --8<-- [start:initialize]
// Introduces the client to the server and prints the server's name and
// version. The Workbench keeps no session, so a client can skip this step.
async Task Initialize(string baseUrl, string token)
{
    var result = await Rpc(baseUrl, token, "initialize", new
    {
        protocolVersion = "2024-11-05",
        capabilities = new { },
        clientInfo = new { name = "cookbook", version = "1.0.0" },
    });
    var info = result["serverInfo"]!;
    Console.WriteLine($"Server: {info["name"]} {info["version"]}");
}
// --8<-- [end:initialize]

// --8<-- [start:list_tools]
// Lists the tools, checks that the two that the program calls are present,
// and prints the arguments that each one requires.
async Task ListTools(string baseUrl, string token)
{
    var result = await Rpc(baseUrl, token, "tools/list", new { });
    // The server lists its tools in no fixed order, so look the two tools
    // up by name.
    var tools = result["tools"]!.AsArray()
        .ToDictionary(t => t!["name"]!.GetValue<string>(), t => t!);
    foreach (var name in new[] { "query_database", "execute_explain" })
    {
        if (!tools.TryGetValue(name, out var tool))
        {
            throw new InvalidOperationException(
                $"The server does not offer {name}");
        }
        var required = tool["inputSchema"]!["required"]!.AsArray()
            .Select(r => r!.GetValue<string>());
        Console.WriteLine($"{name} requires: {string.Join(", ", required)}");
    }
}
// --8<-- [end:list_tools]

// --8<-- [start:call_tool]
// Calls a tool and returns the text of its reply. A tool that fails
// returns a normal result with isError set, so the function checks that
// flag too.
async Task<string> CallTool(string baseUrl, string token, string name,
    object arguments)
{
    var result = await Rpc(baseUrl, token, "tools/call",
        new { name, arguments });
    var text = result["content"]![0]!["text"]!.GetValue<string>();
    if (result["isError"]?.GetValue<bool>() == true)
    {
        throw new InvalidOperationException($"{name} failed: {text}");
    }
    return text;
}
// --8<-- [end:call_tool]

// --8<-- [start:query_database]
// Runs a harmless read-only query with query_database and prints the
// column names and the rows. The reply is text that starts with the
// connection and the query, and then has a "Results" line followed by the
// rows in tab-separated form, so the function prints only what follows
// that line.
async Task QueryDatabase(string baseUrl, string token, long connectionId)
{
    var text = await CallTool(baseUrl, token, "query_database", new
    {
        connection_id = connectionId,
        query = "SELECT 'Hello from the Workbench' AS greeting, "
            + "6 * 7 AS answer",
    });
    var start = text.IndexOf("\nResults", StringComparison.Ordinal);
    if (start < 0)
    {
        throw new InvalidOperationException("The reply had no results");
    }
    // Skip the rest of the Results line, then turn the tabs into commas.
    var lines = text[(start + "\nResults".Length)..].Split('\n')
        .Skip(1)
        .Where(line => line.Length > 0);
    var number = 0;
    foreach (var line in lines)
    {
        var label = number == 0 ? "Columns" : "Row";
        Console.WriteLine($"{label}: {string.Join(", ", line.Split('\t'))}");
        number++;
    }
}
// --8<-- [end:query_database]

// --8<-- [start:execute_explain]
// Plans a query with execute_explain, without running it, and prints the
// type of the first node of the plan. Setting analyze to true would run
// the query.
async Task ExecuteExplain(string baseUrl, string token, long connectionId)
{
    var text = await CallTool(baseUrl, token, "execute_explain", new
    {
        connection_id = connectionId,
        query = "SELECT 1 + 1",
        analyze = false,
    });
    // The plan follows a line of equals signs.
    var match = Regex.Match(text, @"Execution Plan:\n=+\n(\S+)");
    if (!match.Success)
    {
        throw new InvalidOperationException(
            "The reply had no execution plan");
    }
    Console.WriteLine($"Plan starts with: {match.Groups[1].Value}");
}
// --8<-- [end:execute_explain]

// --8<-- [start:main]
try
{
    var (baseUrl, token, connectionId) = Settings();
    await Initialize(baseUrl, token);
    await ListTools(baseUrl, token);
    await QueryDatabase(baseUrl, token, connectionId);
    await ExecuteExplain(baseUrl, token, connectionId);
}
// HttpRequestException covers failures to connect and replies that the
// server rejected, TaskCanceledException covers a request that timed out,
// and the others cover replies that lacked what we need.
catch (Exception e) when (e is HttpRequestException
    or TaskCanceledException or InvalidOperationException or JsonException)
{
    Console.Error.WriteLine($"Error: {e.Message}");
    return 1;
}
return 0;
// --8<-- [end:main]
