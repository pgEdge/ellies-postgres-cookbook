/*
 * Ellie's Postgres Cookbook
 * Holding a conversation with the pgEdge RAG Server, using HttpClient and
 * System.Text.Json.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Net.Http.Json;
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

static string BaseUrl() =>
    EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');
static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");

// The second question does not say which version of the Acme Widget it
// means, so only the first question and its answer, which the model
// receives as history, settle that. The search uses only the current
// question, which is why this one still names the product.
string[] questions =
[
    "How long does the Acme Widget 2.0 take to charge?",
    "And how many hours does the Acme Widget run for once it is charged?",
];

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const int TimeoutSeconds = 300;
// --8<-- [end:config]

// --8<-- [start:ask]
// Returns at most the first 200 characters of a reply.
static string Shorten(string text) =>
    text.Length > 200 ? text[..200] : text;

// Describes an error response, which carries a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
static string ErrorText(string body)
{
    try
    {
        if (JsonNode.Parse(body)?["error"] is JsonObject error &&
            error["code"] is JsonValue codeNode &&
            codeNode.TryGetValue(out string? code))
        {
            return $"{code}: {error["message"]}";
        }
    }
    catch (JsonException)
    {
        // The body is not JSON, so show it as it is.
    }
    return Shorten(body.Trim());
}

// Sends a question and the conversation so far to the pipeline, and
// returns the answer. The server keeps no conversation between requests,
// so history lists the earlier messages, each with a role of user or
// assistant, in order.
static async Task<string> AskAsync(
    HttpClient client, string question, List<Message> history)
{
    var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
    using var response = await client.PostAsync(
        url, JsonContent.Create(new { query = question, messages = history }));
    var body = await response.Content.ReadAsStringAsync();

    // HttpClient treats an error status as a normal response, so check it
    // here.
    if (!response.IsSuccessStatusCode)
    {
        throw new RagException(
            $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
    }

    try
    {
        // TryGetValue fails when the answer holds a different type, such
        // as a number.
        if (JsonNode.Parse(body)?["answer"] is JsonValue answerNode &&
            answerNode.TryGetValue(out string? answer))
        {
            return answer;
        }
    }
    catch (JsonException)
    {
        // The body is not JSON; report it below.
    }
    throw new RagException($"Unexpected response: {Shorten(body)}");
}
// --8<-- [end:ask]

// --8<-- [start:converse]
// Asks each question in turn, printing both sides of the conversation.
// After each answer, the question and the answer join the history that
// the next request carries.
static async Task ConverseAsync(HttpClient client, string[] questions)
{
    var history = new List<Message>();
    foreach (var question in questions)
    {
        var answer = await AskAsync(client, question, history);
        Console.WriteLine($"You: {question}");
        Console.WriteLine($"Assistant: {answer}");
        history.Add(new Message("user", question));
        history.Add(new Message("assistant", answer));
    }
}
// --8<-- [end:converse]

// --8<-- [start:main]
try
{
    // using disposes of the client, and closes its connections, when the
    // block exits, whether or not an error occurred.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    await ConverseAsync(client, questions);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or RagException)
{
    Console.Error.WriteLine($"RAG Server error: {e.Message}");
    return 1;
}

return 0;

// C# requires type declarations to follow the top-level statements, so
// the types that the program uses are declared here, at the end. A
// message is one turn of the conversation; JsonContent writes its
// properties in camel case, as role and content.
record Message(string Role, string Content);

class RagException(string message) : Exception(message);
// --8<-- [end:main]
