/*
 * Ellie's Postgres Cookbook
 * Chatting with the LLM through the AI DBA Workbench API, using
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
// Returns the value of an environment variable, or null if the variable
// is unset or empty, as an unset variable would be.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Reads the settings from the environment.
static (string BaseUrl, string Token) Settings()
{
    var token = EnvValue("WORKBENCH_TOKEN")
        ?? throw new InvalidOperationException("WORKBENCH_TOKEN must be set");
    var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
    return (baseUrl.TrimEnd('/'), token);
}
// --8<-- [end:config]

// --8<-- [start:request]
// One client serves every request. A small model on a CPU can take a while
// to answer, so the timeout is generous.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };

// Sends a request to the API and returns the JSON reply. A request that the
// server rejects throws an error that includes the message from the server.
async Task<JsonNode> Api(string baseUrl, string token, string method,
    string path, object? body = null)
{
    using var request = new HttpRequestMessage(
        new HttpMethod(method), $"{baseUrl}/api/v1{path}");
    request.Headers.Authorization =
        new AuthenticationHeaderValue("Bearer", token);
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
    return JsonNode.Parse(text)
        ?? throw new InvalidOperationException(
            $"{method} {path} returned no JSON");
}
// --8<-- [end:request]

// --8<-- [start:providers]
// Prints the default provider and model, which the chat endpoint uses when
// a request names neither.
async Task ShowProvider(string baseUrl, string token)
{
    var reply = await Api(baseUrl, token, "GET", "/llm/providers");
    var provider = reply["providers"]?.AsArray()
        .FirstOrDefault(p => p?["isDefault"]?.GetValue<bool>() == true)
        ?? throw new InvalidOperationException(
            "The Workbench has no default LLM provider");
    Console.WriteLine(
        $"Provider: {provider["name"]} (model {reply["defaultModel"]})");
}
// --8<-- [end:providers]

// --8<-- [start:chat]
// Sends a conversation to the model and returns the reply. The messages are
// the conversation so far, each with a role of user or assistant and some
// content.
async Task<JsonNode> Chat(string baseUrl, string token,
    List<object> messages) =>
    await Api(baseUrl, token, "POST", "/llm/chat", new { messages });

// Returns the text of a reply on a single line. A small model may spread
// its answer over several lines, so the function joins the text blocks and
// collapses the white space. It fails when the reply holds no text.
static string ReplyText(JsonNode reply)
{
    var blocks = (reply["content"]?.AsArray() ?? new JsonArray())
        .Where(b => b?["type"]?.GetValue<string>() == "text")
        .Select(b => b!["text"]?.GetValue<string>() ?? "");
    var text = Regex.Replace(string.Join(" ", blocks).Trim(), @"\s+", " ");
    if (text.Length == 0)
    {
        throw new InvalidOperationException("The model returned no text");
    }
    return text;
}
// --8<-- [end:chat]

// --8<-- [start:main]
try
{
    var (baseUrl, token) = Settings();
    await ShowProvider(baseUrl, token);

    // The first message starts the conversation.
    var question = "Name one type of PostgreSQL index, in one sentence.";
    var messages = new List<object>
    {
        new { role = "user", content = question },
    };
    var text = ReplyText(await Chat(baseUrl, token, messages));
    Console.WriteLine($"Reply: {text}");

    // The server keeps no conversation, so the follow-up repeats the
    // earlier messages, including the model's reply, and adds the new
    // question.
    messages.Add(new { role = "assistant", content = text });
    messages.Add(new
    {
        role = "user",
        content = "Summarise your answer in five words.",
    });
    var followUp = await Chat(baseUrl, token, messages);
    Console.WriteLine($"Follow-up reply: {ReplyText(followUp)}");
    Console.WriteLine($"Stop reason: {followUp["stop_reason"]}");
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
