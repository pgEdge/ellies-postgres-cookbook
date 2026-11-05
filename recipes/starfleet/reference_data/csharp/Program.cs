/*
 * Ellie's Postgres Cookbook
 * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
 * Starfleet Managed API offers, using HttpClient and System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Globalization;
using System.Net.Http.Headers;
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

var cfg = Settings();
// --8<-- [end:config]

// --8<-- [start:token]
// One client serves every request. Its timeout covers the whole exchange,
// the body of the reply included.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

// Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
// throws an HttpRequestException that includes the message from the API.
async Task<JsonNode> Send(HttpRequestMessage request, string path)
{
    using var response = await http.SendAsync(request);
    var text = await response.Content.ReadAsStringAsync();
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"{request.Method} {path} failed with status "
            + $"{(int)response.StatusCode}: {text.Trim()}",
            null, response.StatusCode);
    }
    return JsonNode.Parse(text)
        ?? throw new InvalidOperationException($"the reply to {path} is empty");
}

// Exchanges the client ID and secret for an access token, which the
// Managed API accepts as a bearer token until it expires.
async Task<string> GetToken()
{
    if (cfg.ClientId is null || cfg.ClientSecret is null)
    {
        throw new InvalidOperationException(
            "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
    }

    const string path = "/account/v1/oauth/token";
    using var request = new HttpRequestMessage(HttpMethod.Post, cfg.BaseUrl + path)
    {
        Content = new StringContent(JsonSerializer.Serialize(new
        {
            grant_type = "client_credentials",
            client_id = cfg.ClientId,
            client_secret = cfg.ClientSecret,
        }), Encoding.UTF8, "application/json"),
    };
    return (await Send(request, path))["access_token"]!.ToString();
}
// --8<-- [end:token]

// --8<-- [start:api]
// Sends an authenticated GET request to the Managed API and returns the
// decoded JSON reply. The query, if there is one, follows the path.
async Task<JsonNode> ApiGet(string token, string path, string query = "")
{
    var url = $"{cfg.BaseUrl}/managed/v1{path}"
        + (query.Length == 0 ? "" : $"?{query}");
    using var request = new HttpRequestMessage(HttpMethod.Get, url);
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    return await Send(request, path);
}
// --8<-- [end:api]

// --8<-- [start:regions]
// Returns the identifiers of the regions that can host a database.
async Task<List<string>> ListRegions(string token) =>
    (await ApiGet(token, "/regions")).AsArray()
        .Select(region => region!["region"]!.ToString())
        .ToList();
// --8<-- [end:regions]

// --8<-- [start:sizes]
// Returns a description of each size, smallest first.
async Task<List<string>> ListSizes(string token)
{
    // The pricing option asks the API to include each size's price, which
    // takes a little longer because the API looks it up from billing.
    var sizes = new List<string>();
    foreach (var size in (await ApiGet(token, "/sizes", "include=pricing")).AsArray())
    {
        var line = $"{size!["name"]}: {size["connections"]} connections, "
            + $"{size["storage_size"]} storage";
        // A size with no configured price omits the pricing field. The
        // amount is in the smallest unit of the currency, such as cents.
        // The invariant culture keeps the decimal point a full stop.
        if (size["pricing"] is JsonObject price)
        {
            var amount = price["price_amount"]!.GetValue<long>() / 100.0;
            line += $", {amount.ToString("F2", CultureInfo.InvariantCulture)} "
                + $"{price["currency"]} per {price["billing_interval"]}";
        }
        sizes.Add(line);
    }
    return sizes;
}
// --8<-- [end:sizes]

// --8<-- [start:versions]
// Returns the PostgreSQL major versions, newest first, marking the one that
// a new database gets by default.
async Task<List<string>> ListVersions(string token) =>
    (await ApiGet(token, "/pg-versions")).AsArray()
        .Select(version => version!["version"]!.ToString()
            + (version["default"]?.GetValue<bool>() == true ? " (default)" : ""))
        .ToList();
// --8<-- [end:versions]

// --8<-- [start:main]
try
{
    var token = await GetToken();

    Console.WriteLine("Regions:");
    foreach (var region in await ListRegions(token))
    {
        Console.WriteLine($"  {region}");
    }

    Console.WriteLine("Sizes (smallest first):");
    foreach (var size in await ListSizes(token))
    {
        Console.WriteLine($"  {size}");
    }

    Console.WriteLine("PostgreSQL versions:");
    foreach (var version in await ListVersions(token))
    {
        Console.WriteLine($"  {version}");
    }
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
