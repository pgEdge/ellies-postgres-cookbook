/*
 * Ellie's Postgres Cookbook
 * Listing and acknowledging alerts with the AI DBA Workbench API, using
 * HttpClient and System.Text.Json.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
// --8<-- [end:imports]

// --8<-- [start:config]
// The rule that the program makes fire. The metric_staleness rule alerts
// when a probe's data is out of date, and the alerter checks it every
// minute.
const string RuleName = "metric_staleness";

// The longest the whole run waits for alerts. The alerter evaluates its
// rules once a minute and clears an alert up to 30 seconds after it fires,
// so this allows for waiting out the alert from an earlier run, one alert
// that clears before the program can acknowledge it, and a second
// evaluation.
var waitTime = TimeSpan.FromSeconds(150);

// How often the program polls the alerts.
var pollInterval = TimeSpan.FromMilliseconds(500);

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
var cfg = (BaseUrl: "", Token: "", ConnectionId: "");

// Sends a request to the API and returns the JSON reply, or null if the
// reply has no body. The path may include a query string. A request that
// the server rejects throws an error that includes the message from the
// server.
async Task<JsonNode?> Api(string method, string path, object? body = null)
{
    using var request = new HttpRequestMessage(
        new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
    request.Headers.Authorization =
        new AuthenticationHeaderValue("Bearer", cfg.Token);
    if (body is not null)
    {
        request.Content = JsonContent.Create(body);
    }

    using var response = await http.SendAsync(request);
    var text = await response.Content.ReadAsStringAsync();
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"{method} {path} failed with status {(int)response.StatusCode}: "
            + text.Trim());
    }
    return text.Length == 0 ? null : JsonNode.Parse(text);
}
// --8<-- [end:request]

// --8<-- [start:find_rule]
// Returns the ID of an alert rule, given its name.
async Task<long> FindRule(string name)
{
    var rules = (await Api("GET", "/alert-rules"))?.AsArray()
        ?? throw new InvalidOperationException("The reply had no rules");
    var rule = rules.FirstOrDefault(
        r => r?["name"]?.GetValue<string>() == name)
        ?? throw new InvalidOperationException(
            $"There is no alert rule named '{name}'");
    return rule["id"]!.GetValue<long>();
}
// --8<-- [end:find_rule]

// --8<-- [start:set_override]
// Overrides the threshold of a rule for one server. A threshold of -1 is
// below any value that the staleness ratio can take, so the rule is
// violated on the next evaluation.
async Task SetOverride(long ruleId) =>
    await Api("PUT", $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}",
        new { @operator = ">", threshold = -1, severity = "info",
            enabled = true });
// --8<-- [end:set_override]

// --8<-- [start:wait_for_alert]
// Returns the threshold alerts for the server that have the given status.
// The request asks for the most alerts that the API returns at once, so
// that the result does not depend on the first 100 alerts of a busy
// Workbench.
async Task<List<JsonNode>> ListAlerts(string status)
{
    var query = $"connection_id={Uri.EscapeDataString(cfg.ConnectionId)}"
        + $"&status={status}&alert_type=threshold&limit=1000";
    var reply = await Api("GET", $"/alerts?{query}");
    return reply?["alerts"]?.AsArray().OfType<JsonNode>().ToList()
        ?? throw new InvalidOperationException("The reply had no alerts");
}

// Returns the active alerts that the given rule raised for the server.
async Task<List<JsonNode>> ActiveAlerts(long ruleId) =>
    (await ListAlerts("active"))
        .Where(a => a["rule_id"]?.GetValue<long>() == ruleId)
        .ToList();

// Waits until the rule has no active alert. The alerter raises no new
// alert for a rule while one is active, so an alert left by an earlier
// run, which clears within 30 seconds, would otherwise stand in for the
// one that this run causes.
async Task WaitUntilQuiet(long ruleId, Stopwatch clock)
{
    while ((await ActiveAlerts(ruleId)).Count > 0)
    {
        if (clock.Elapsed >= waitTime)
        {
            throw new InvalidOperationException(
                "An earlier alert did not clear in time");
        }
        await Task.Delay(pollInterval);
    }
}

// Polls until the given rule raises an alert, and returns it. The alert
// clears itself within 30 seconds of firing, so the program polls twice a
// second.
async Task<JsonNode> WaitForAlert(long ruleId, Stopwatch clock)
{
    while (true)
    {
        var alerts = await ActiveAlerts(ruleId);
        if (alerts.Count > 0)
        {
            return alerts[0];
        }
        if (clock.Elapsed >= waitTime)
        {
            throw new InvalidOperationException(
                $"No alert was raised within {waitTime.TotalSeconds} seconds");
        }
        await Task.Delay(pollInterval);
    }
}
// --8<-- [end:wait_for_alert]

// --8<-- [start:acknowledge]
// Acknowledges an alert, with a message that the interface shows.
async Task AcknowledgeAlert(long alertId) =>
    await Api("POST", "/alerts/acknowledge",
        new { alert_id = alertId, message = "Acknowledged by the cookbook" });
// --8<-- [end:acknowledge]

// --8<-- [start:check]
// Returns the status of an alert, found by its ID in the list of
// acknowledged alerts.
async Task<string> AlertStatus(long alertId)
{
    var alert = (await ListAlerts("acknowledged"))
        .FirstOrDefault(a => a["id"]?.GetValue<long>() == alertId)
        ?? throw new InvalidOperationException(
            "The alert is missing from the acknowledged alerts");
    return alert["status"]!.GetValue<string>();
}
// --8<-- [end:check]

// --8<-- [start:unacknowledge]
// Returns an acknowledged alert to the active state. The alerter clears
// only active alerts, so an alert that stays acknowledged also stops the
// rule from raising a new one.
async Task UnacknowledgeAlert(long alertId) =>
    await Api("DELETE", $"/alerts/acknowledge?alert_id={alertId}");
// --8<-- [end:unacknowledge]

// --8<-- [start:remove_override]
// Removes the override, so that the rule reverts to its default threshold.
async Task RemoveOverride(long ruleId) =>
    await Api("DELETE",
        $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}");
// --8<-- [end:remove_override]

// --8<-- [start:main]
// Reports whether an error is one that the program expects: a failure to
// connect, a reply that the server rejected, a request that timed out, or
// a reply that lacked what we need.
static bool Expected(Exception e) => e is HttpRequestException
    or TaskCanceledException or InvalidOperationException or JsonException;

// Reports whether a list of alerts includes the one with an ID.
static bool Contains(List<JsonNode> alerts, long alertId) =>
    alerts.Any(a => a["id"]?.GetValue<long>() == alertId);

long? overrideRule = null;
long? acknowledgedAlert = null;
var status = 0;
try
{
    cfg = Settings();
    var clock = Stopwatch.StartNew();

    var ruleId = await FindRule(RuleName);
    Console.WriteLine($"Found the rule '{RuleName}'");

    // An alert from an earlier run may still be active.
    await WaitUntilQuiet(ruleId, clock);

    // Record the override first and remove it at the end, so that a
    // failed run does not leave the server raising alerts.
    overrideRule = ruleId;
    await SetOverride(ruleId);
    Console.WriteLine("Set an override that makes the rule fire");

    Console.WriteLine("Waiting for the alerter to raise an alert");
    JsonNode alert;
    while (true)
    {
        alert = await WaitForAlert(ruleId, clock);
        var raisedId = alert["id"]!.GetValue<long>();

        // Record the alert before acknowledging it, so that the clean-up
        // returns it to the active state even if the request times out
        // after the server has acted on it.
        acknowledgedAlert = raisedId;
        try
        {
            await AcknowledgeAlert(raisedId);
            break;
        }
        catch (Exception e) when (Expected(e))
        {
            // The alerter may have cleared the alert since the poll. The
            // override is still in place, so the rule fires again at the
            // next evaluation; any other failure is real.
            if (Contains(await ActiveAlerts(ruleId), raisedId))
            {
                // The server did not acknowledge it, so there is nothing
                // to undo.
                acknowledgedAlert = null;
                throw;
            }
            // If the server acted on a request that timed out, the alert
            // is acknowledged and must go back to active. When that fails,
            // the error propagates and the clean-up tries again, because
            // acknowledgedAlert is still set.
            if (Contains(await ListAlerts("acknowledged"), raisedId))
            {
                await UnacknowledgeAlert(raisedId);
            }
            acknowledgedAlert = null;
            Console.Error.WriteLine(
                "The alert cleared first; waiting for the next one");
        }
    }
    var alertId = alert["id"]!.GetValue<long>();
    Console.WriteLine(
        $"An alert is active (severity: {alert["severity"]})");
    Console.WriteLine("Acknowledged the alert");

    Console.WriteLine($"The alert is now {await AlertStatus(alertId)}");

    await UnacknowledgeAlert(alertId);
    acknowledgedAlert = null;
    Console.WriteLine("Returned the alert to the active state");

    await RemoveOverride(ruleId);
    overrideRule = null;
    Console.WriteLine("Removed the override");
}
catch (Exception e) when (Expected(e))
{
    Console.Error.WriteLine($"Error: {e.Message}");
    status = 1;
}

// Undo the changes whether or not a step failed, so that the server does
// not keep raising alerts or hold an acknowledged one.
var undo = new List<Func<Task>>();
if (acknowledgedAlert is long pendingAlert)
{
    undo.Add(() => UnacknowledgeAlert(pendingAlert));
}
if (overrideRule is long pendingRule)
{
    undo.Add(() => RemoveOverride(pendingRule));
}
foreach (var step in undo)
{
    try
    {
        await step();
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: could not undo a change: {e.Message}");
        status = 1;
    }
}

return status;
// --8<-- [end:main]
