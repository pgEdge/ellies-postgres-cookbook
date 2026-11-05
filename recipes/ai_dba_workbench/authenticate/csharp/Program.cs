/*
 * Ellie's Postgres Cookbook
 * Authenticating with the AI DBA Workbench API, using HttpClient and
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
static (string BaseUrl, string Username, string Password) Settings()
{
    var username = EnvValue("WORKBENCH_USERNAME");
    var password = EnvValue("WORKBENCH_PASSWORD");
    if (username is null || password is null)
    {
        throw new InvalidOperationException(
            "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
    }
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    return (baseUrl.TrimEnd('/'), username, password);
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

// --8<-- [start:user_info]
// Returns the user that a token belongs to, with its superuser flag.
async Task<string> UserInfo(string baseUrl, string token)
{
    var info = await ApiJson("GET", baseUrl, "/user/info", token);
    // A bool would print as True or False, so spell the flag out.
    var superuser = info["is_superuser"]!.GetValue<bool>() ? "true" : "false";
    return $"{info["username"]!.GetValue<string>()} (superuser: {superuser})";
}
// --8<-- [end:user_info]

// --8<-- [start:create_token]
// Creates an API token for a user and returns its ID and its value. The
// server shows the value only once. The token expires after an hour.
async Task<(long Id, string Token)> CreateToken(string baseUrl,
    string session, string owner, string annotation)
{
    var created = await ApiJson("POST", baseUrl, "/rbac/tokens", session,
        new { owner_username = owner, annotation, expires_in = "1h" });
    return (created["id"]!.GetValue<long>(),
        created["token"]!.GetValue<string>());
}
// --8<-- [end:create_token]

// --8<-- [start:delete_token]
// Deletes an API token by its ID.
async Task DeleteToken(string baseUrl, string session, long tokenId)
{
    using var response =
        await Api("DELETE", baseUrl, $"/rbac/tokens/{tokenId}", session);
}
// --8<-- [end:delete_token]

// --8<-- [start:main]
var status = 0;
var baseUrl = "";
var session = "";
long? tokenId = null;
try
{
    var (url, username, password) = Settings();
    baseUrl = url;

    session = await Login(baseUrl, username, password);
    Console.WriteLine("Logged in with a session token");
    Console.WriteLine(
        $"Session token belongs to {await UserInfo(baseUrl, session)}");

    var created = await CreateToken(baseUrl, session, username,
        "cookbook-authenticate");
    tokenId = created.Id;
    Console.WriteLine("Created the API token 'cookbook-authenticate'");
    Console.WriteLine(
        $"API token belongs to {await UserInfo(baseUrl, created.Token)}");
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

// Delete the token whether or not a later step failed, so that a failed
// run does not leave a token behind.
if (tokenId is not null)
{
    try
    {
        await DeleteToken(baseUrl, session, tokenId.Value);
        Console.WriteLine("Deleted the API token");
    }
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException)
    {
        Console.Error.WriteLine(
            $"Error: could not delete the token: {e.Message}");
        status = 1;
    }
}

return status;
// --8<-- [end:main]
