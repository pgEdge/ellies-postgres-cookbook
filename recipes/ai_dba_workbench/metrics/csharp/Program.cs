/*
 * Ellie's Postgres Cookbook
 * Querying metrics and top queries with the AI DBA Workbench API, using
 * HttpClient and System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Globalization;
using System.Net.Http.Headers;
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
static (string BaseUrl, string Token, string ConnectionId) Settings()
{
    var token = EnvValue("WORKBENCH_TOKEN");
    var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
    if (token is null || connectionId is null)
    {
        throw new InvalidOperationException(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
    }
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    return (baseUrl.TrimEnd('/'), token, connectionId);
}
// --8<-- [end:config]

// --8<-- [start:request]
// One client serves every request, with a timeout for each.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

// Sends a GET request to the API, with the parameters in the query string,
// and returns the JSON reply. A request that the server rejects throws an
// error that includes the message from the server.
async Task<JsonArray> Api(string baseUrl, string token, string path,
    Dictionary<string, string> parameters)
{
    var query = string.Join("&", parameters.Select(p =>
        $"{Uri.EscapeDataString(p.Key)}={Uri.EscapeDataString(p.Value)}"));
    using var request = new HttpRequestMessage(HttpMethod.Get,
        $"{baseUrl}/api/v1{path}?{query}");
    request.Headers.Authorization =
        new AuthenticationHeaderValue("Bearer", token);

    using var response = await http.SendAsync(request);
    var text = await response.Content.ReadAsStringAsync();
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"GET {path} failed with status {(int)response.StatusCode}: "
            + text.Trim());
    }
    return JsonNode.Parse(text)?.AsArray()
        ?? throw new InvalidOperationException($"GET {path} returned no JSON");
}
// --8<-- [end:request]

// --8<-- [start:query_metrics]
// Returns a number as plain decimal text, without an exponent or trailing
// zeros, and with a full stop whatever the locale.
static string Plain(double value) =>
    value.ToString("0.###############", CultureInfo.InvariantCulture);

// Prints one line for each series that the pg_stat_database probe
// collected over the last hour, in six buckets: the metric, the number of
// points, and the latest value.
async Task QueryMetrics(string baseUrl, string token, string connectionId)
{
    var series = await Api(baseUrl, token, "/metrics/query", new()
    {
        ["connection_id"] = connectionId,
        ["probe_name"] = "pg_stat_database",
        ["time_range"] = "1h",
        ["buckets"] = "6",
        ["metrics"] = "numbackends,xact_commit",
    });
    if (series.Count == 0)
    {
        throw new InvalidOperationException(
            "The Workbench returned no series; has the collector run yet?");
    }
    foreach (var s in series)
    {
        var name = s!["name"]!.GetValue<string>();
        var points = s["data"]?.AsArray();
        if (points is null || points.Count == 0)
        {
            Console.WriteLine($"{name}: no data");
            continue;
        }
        var latest = points[^1]!["value"]!.GetValue<double>();
        Console.WriteLine(
            $"{name}: {points.Count} points, latest {Plain(latest)}");
    }
}
// --8<-- [end:query_metrics]

// --8<-- [start:top_queries]
// Prints the queries that have used the most execution time, as the
// pg_stat_statements extension on the monitored server recorded them. The
// query text is cut to 50 characters on one line.
async Task TopQueries(string baseUrl, string token, string connectionId)
{
    var queries = await Api(baseUrl, token, "/metrics/top-queries", new()
    {
        ["connection_id"] = connectionId,
        ["limit"] = "5",
        ["order_by"] = "total_exec_time",
        ["exclude_collector"] = "true",
    });
    if (queries.Count == 0)
    {
        Console.WriteLine(
            "No statements recorded (is pg_stat_statements installed?)");
        return;
    }

    Console.WriteLine("Top queries by total execution time:");
    var rank = 1;
    foreach (var q in queries)
    {
        var text = Regex.Replace(q!["query"]!.GetValue<string>().Trim(),
            @"\s+", " ");
        // Count characters, not UTF-16 units, when cutting the text.
        text = string.Concat(text.EnumerateRunes().Take(50));
        var mean = Math.Round(q["mean_exec_time"]!.GetValue<double>(), 2,
            MidpointRounding.AwayFromZero);
        Console.WriteLine($"{rank}. {q["calls"]!.GetValue<long>()} calls, "
            + $"{Plain(mean)} ms mean: {text}");
        rank++;
    }
}
// --8<-- [end:top_queries]

// --8<-- [start:main]
try
{
    var (baseUrl, token, connectionId) = Settings();
    await QueryMetrics(baseUrl, token, connectionId);
    await TopQueries(baseUrl, token, connectionId);
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
