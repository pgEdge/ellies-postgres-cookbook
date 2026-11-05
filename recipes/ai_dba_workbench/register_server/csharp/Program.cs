/*
 * Ellie's Postgres Cookbook
 * Registering a server to monitor with the AI DBA Workbench API, using
 * HttpClient and System.Text.Json.
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
const string ServerName = "cookbook-register-server";

// Returns the value of an environment variable, or null if the variable
// is unset or empty, as an unset variable would be.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Reads the settings from the environment.
static (string BaseUrl, string Username, string Password,
    string ConnectionId, string ServerPassword) Settings()
{
    var username = EnvValue("WORKBENCH_USERNAME");
    var password = EnvValue("WORKBENCH_PASSWORD");
    var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
    if (username is null || password is null || connectionId is null)
    {
        throw new InvalidOperationException(
            "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
            + "WORKBENCH_CONNECTION_ID must be set");
    }
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    // The Workbench refuses to register a server without a password, even
    // one that uses trust authentication, so fall back to a placeholder.
    var serverPassword =
        EnvValue("PGPASSWORD") ?? "unused-with-trust-authentication";
    return (baseUrl.TrimEnd('/'), username, password, connectionId,
        serverPassword);
}
// --8<-- [end:config]

// --8<-- [start:request]
// One client serves every request, with a timeout for each. The handler
// keeps no cookies, so the session token goes only where the program
// sends it.
var http = new HttpClient(new SocketsHttpHandler { UseCookies = false })
{
    Timeout = TimeSpan.FromSeconds(30),
};

// Sends a request to the API and returns the response, which the caller
// must dispose of. A request that the server rejects throws an error that
// includes the message from the server.
async Task<HttpResponseMessage> Api(string method, string baseUrl,
    string path, string? token = null, object? body = null)
{
    using var request = new HttpRequestMessage(
        new HttpMethod(method), $"{baseUrl}/api/v1{path}");
    if (token is not null)
    {
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    }
    if (body is not null)
    {
        request.Content = JsonContent.Create(body);
    }

    var response = await http.SendAsync(request);
    var code = (int)response.StatusCode;
    if (code >= 400)
    {
        var text = (await response.Content.ReadAsStringAsync()).Trim();
        response.Dispose();
        throw new HttpRequestException(
            $"{method} {path} failed with status {code}: {text}");
    }
    return response;
}

// Sends a request to the API and returns the JSON reply.
async Task<JsonNode> ApiJson(string method, string baseUrl, string path,
    string? token = null, object? body = null)
{
    using var response = await Api(method, baseUrl, path, token, body);
    return JsonNode.Parse(await response.Content.ReadAsStringAsync())
        ?? throw new InvalidOperationException(
            $"{method} {path} returned no JSON");
}
// --8<-- [end:request]

// --8<-- [start:login]
// Logs in and returns the session token. The server returns the token in a
// session_token cookie, not in the body of the reply.
async Task<string> Login(string baseUrl, string username, string password)
{
    using var response = await Api("POST", baseUrl, "/auth/login",
        body: new { username, password });
    if (response.Headers.TryGetValues("Set-Cookie", out var cookies))
    {
        foreach (var cookie in cookies)
        {
            var match = Regex.Match(cookie, "^session_token=([^;]*)");
            if (match.Success)
            {
                return match.Groups[1].Value;
            }
        }
    }
    throw new InvalidOperationException(
        "The login reply had no session_token cookie");
}
// --8<-- [end:login]

// --8<-- [start:lookup]
// Returns the details of an existing connection, which the program uses
// as the address of the server to register.
async Task<JsonNode> GetConnection(string baseUrl, string session,
    string connectionId) =>
    await ApiJson("GET", baseUrl, $"/connections/{connectionId}", session);
// --8<-- [end:lookup]

// --8<-- [start:register]
// Registers a server and returns the ID of the new connection. The address
// comes from an existing connection. The request must include a password,
// and a description, which the server needs in version 1.0.0.
async Task<long> RegisterServer(string baseUrl, string session,
    string name, JsonNode template, string password)
{
    // A JSON node belongs to one parent at a time, so the program copies
    // each field that it takes from the existing connection.
    var body = new JsonObject
    {
        ["name"] = name,
        ["description"] = "Registered by the cookbook",
        ["host"] = template["host"]?.DeepClone(),
        ["port"] = template["port"]?.DeepClone(),
        ["database_name"] = template["database_name"]?.DeepClone(),
        ["username"] = template["username"]?.DeepClone(),
        ["ssl_mode"] = template["ssl_mode"]?.DeepClone(),
        ["password"] = password,
        ["is_monitored"] = true,
        ["is_shared"] = false,
    };
    var created = await ApiJson("POST", baseUrl, "/connections", session,
        body);
    return created["id"]!.GetValue<long>();
}
// --8<-- [end:register]

// --8<-- [start:list]
// Returns the named connection from the list, or null if the list has no
// such connection.
async Task<JsonNode?> FindConnection(string baseUrl, string session,
    string name)
{
    var connections = await ApiJson("GET", baseUrl, "/connections", session);
    return connections.AsArray().FirstOrDefault(
        c => c?["name"]?.GetValue<string>() == name);
}
// --8<-- [end:list]

// --8<-- [start:delete]
// Deletes a connection by its ID.
async Task DeleteConnection(string baseUrl, string session,
    long connectionId)
{
    using var response = await Api("DELETE", baseUrl,
        $"/connections/{connectionId}", session);
}
// --8<-- [end:delete]

// --8<-- [start:main]
var status = 0;
var baseUrl = "";
var session = "";
long? newId = null;
try
{
    var settings = Settings();
    baseUrl = settings.BaseUrl;

    session = await Login(baseUrl, settings.Username, settings.Password);
    var template = await GetConnection(baseUrl, session,
        settings.ConnectionId);

    newId = await RegisterServer(baseUrl, session, ServerName, template,
        settings.ServerPassword);
    Console.WriteLine($"Registered the server '{ServerName}'");

    var found = await FindConnection(baseUrl, session, ServerName)
        ?? throw new InvalidOperationException(
            "The new connection is missing from the list");
    // A bool would print as True or False, so spell the flag out.
    var monitored = found["is_monitored"]!.GetValue<bool>() ? "true" : "false";
    Console.WriteLine(
        $"Found '{ServerName}' in the list (monitored: {monitored})");

    await DeleteConnection(baseUrl, session, newId.Value);
    newId = null;
    Console.WriteLine("Deleted the connection");

    if (await FindConnection(baseUrl, session, ServerName) is not null)
    {
        throw new InvalidOperationException(
            "The connection is still in the list");
    }
    Console.WriteLine("The connection is no longer in the list");
}
// HttpRequestException covers failures to connect and replies that the
// server rejected, TaskCanceledException covers a request that timed out,
// and the others cover replies that lacked what we need.
catch (Exception e) when (e is HttpRequestException
    or TaskCanceledException or InvalidOperationException or JsonException)
{
    Console.Error.WriteLine($"Error: {e.Message}");
    status = 1;
}
finally
{
    // Delete the connection whether or not a later step failed, so that a
    // failed run does not leave a server registered. The finally block also
    // runs for an error that the catch does not handle.
    if (newId is not null)
    {
        try
        {
            await DeleteConnection(baseUrl, session, newId.Value);
        }
        catch (Exception e) when (e is HttpRequestException
            or TaskCanceledException)
        {
            Console.Error.WriteLine(
                $"Error: could not delete the connection: {e.Message}");
            status = 1;
        }
    }
}

return status;
// --8<-- [end:main]
