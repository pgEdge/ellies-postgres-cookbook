/*
 * Ellie's Postgres Cookbook
 * Getting an access token for the pgEdge Starfleet Managed API, using
 * HttpClient and System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
// --8<-- [end:imports]

// --8<-- [start:config]
// Returns the value of an environment variable, or null if the variable
// is unset or empty, as an unset variable would be.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Reads the API settings from the environment. The client ID and secret
// have no defaults, so a missing value becomes null, and the token request
// reports it.
static (string BaseUrl, string? ClientId, string? ClientSecret) Settings() =>
    ((EnvValue("STARFLEET_API_URL") ?? "https://api.pgedge.com").TrimEnd('/'),
        EnvValue("STARFLEET_CLIENT_ID"),
        EnvValue("STARFLEET_CLIENT_SECRET"));
// --8<-- [end:config]

// --8<-- [start:token]
// One client serves every request. Its timeout covers the whole exchange,
// the body of the reply included.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

// Exchanges the client ID and secret for an access token. The token
// endpoint belongs to the account API, and accepts the OAuth 2.0 client
// credentials grant as a JSON body.
async Task<JsonNode> GetToken((string BaseUrl, string? ClientId,
    string? ClientSecret) cfg)
{
    if (cfg.ClientId is null || cfg.ClientSecret is null)
    {
        throw new InvalidOperationException(
            "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
    }

    const string path = "/account/v1/oauth/token";
    var body = JsonSerializer.Serialize(new
    {
        grant_type = "client_credentials",
        client_id = cfg.ClientId,
        client_secret = cfg.ClientSecret,
    });
    using var response = await http.PostAsync(cfg.BaseUrl + path,
        new StringContent(body, Encoding.UTF8, "application/json"));
    var text = await response.Content.ReadAsStringAsync();
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"POST {path} failed with status {(int)response.StatusCode}: "
            + text.Trim(), null, response.StatusCode);
    }
    var token = JsonNode.Parse(text);
    if (token?["access_token"]?.ToString() is not { Length: > 0 })
    {
        throw new InvalidOperationException(
            "the token response has no access token");
    }
    return token;
}
// --8<-- [end:token]

// --8<-- [start:main]
try
{
    var token = await GetToken(Settings());
    // Never print the token itself; it grants access to the account.
    Console.WriteLine($"Token type: {token["token_type"]}");
    Console.WriteLine(
        $"Token length: {token["access_token"]!.ToString().Length} characters");
    Console.WriteLine($"Expires in: {token["expires_in"]} seconds");
}
// HttpRequestException covers failures to connect and error replies from
// the API, and HttpClient throws TaskCanceledException when a request
// times out.
catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
{
    Console.Error.WriteLine($"API error: {e.Message}");
    return 1;
}
// JsonException covers a reply that is not JSON, and
// InvalidOperationException covers settings and replies that the program
// cannot use.
catch (Exception e) when (e is JsonException or InvalidOperationException)
{
    Console.Error.WriteLine($"Error: {e.Message}");
    return 1;
}

return 0;
// --8<-- [end:main]
