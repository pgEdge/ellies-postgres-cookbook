/*
 * Ellie's Postgres Cookbook
 * Exploring a schema through the pgEdge Postgres MCP Server, using
 * HttpClient and System.Text.Json.
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
using System.Text.RegularExpressions;
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

// The schema and table that scripts/start_postgres_mcp.sh creates.
const string Schema = "cookbook_mcp";
const string Table = "products";

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

// Calls a tool with tools/call and returns the text of its reply. The
// server answers a JSON-RPC error with HTTP status 200, and a tool that
// fails returns a normal result with isError set, so the function checks
// for both as well as the HTTP status.
static async Task<string> CallToolAsync(HttpClient client, string name, JsonObject arguments)
{
    var message = new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = "tools/call",
        ["params"] = new JsonObject { ["name"] = name, ["arguments"] = arguments },
    };
    using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
    {
        Content = new StringContent(
            message.ToJsonString(), Encoding.UTF8, "application/json"),
    };
    request.Headers.Add("Authorization", $"Bearer {Token()}");
    using var response = await client.SendAsync(request);
    var body = await response.Content.ReadAsStringAsync();
    if (response.StatusCode != HttpStatusCode.OK)
    {
        throw new McpException(
            $"{name} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
    }
    var reply = ParseObject(body);
    if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
    {
        throw new McpException($"{name} failed: unexpected response: {Shorten(body)}");
    }
    if (reply.ContainsKey("error"))
    {
        throw new McpException($"{name} failed: {reply["error"]?["message"]}");
    }
    var result = reply["result"];
    if (result?["content"]?[0]?["text"] is not JsonValue textValue ||
        !textValue.TryGetValue(out string? text))
    {
        throw new McpException($"{name} failed: unexpected result: {Shorten(body)}");
    }
    if (result["isError"] is JsonValue isError &&
        isError.TryGetValue(out bool failed) && failed)
    {
        throw new McpException($"{name} failed: {text}");
    }
    return text;
}
// --8<-- [end:config]

// --8<-- [start:parse_tsv]
// Reads the table in a tool's reply into a list of rows, each a dictionary
// keyed by column name. The reply starts with a line or two about the
// database, and then has a header line and one line for each row, with the
// values separated by tabs. The server writes a tab or a newline inside a
// value as \t or \n, so splitting on them is safe. The header is the first
// line that starts with "schema", the first column of every table that
// get_schema_info returns.
static List<Dictionary<string, string>> ParseTsv(string text)
{
    var lines = text.Split('\n');
    var start = Array.FindIndex(lines, line => line.StartsWith("schema\t"));
    if (start < 0)
    {
        throw new McpException($"The reply had no table: {Shorten(text)}");
    }
    var header = lines[start].Split('\t');
    var rows = new List<Dictionary<string, string>>();
    foreach (var line in lines.Skip(start + 1).Where(line => line.Length > 0))
    {
        var values = line.Split('\t');
        rows.Add(header.Zip(values).ToDictionary(pair => pair.First, pair => pair.Second));
    }
    return rows;
}
// --8<-- [end:parse_tsv]

// --8<-- [start:list_tables]
// Lists the tables in the schema with their comments. With compact set to
// true, get_schema_info returns one line for each table, without its
// columns, which suits a first look at a large database.
static async Task ListTablesAsync(HttpClient client)
{
    var text = await CallToolAsync(client, "get_schema_info", new JsonObject
    {
        ["schema_name"] = Schema,
        ["compact"] = true,
    });
    Console.WriteLine($"Tables in {Schema}:");
    foreach (var row in ParseTsv(text))
    {
        var comment = row.GetValueOrDefault("table_desc");
        Console.WriteLine(
            $"- {row["table"]}: {(string.IsNullOrEmpty(comment) ? "(no comment)" : comment)}");
    }
}
// --8<-- [end:list_tables]

// --8<-- [start:describe_table]
// Lists the columns of one table with their types. Given a table_name,
// get_schema_info returns one line for each column, which also carries the
// table's details.
static async Task DescribeTableAsync(HttpClient client)
{
    var text = await CallToolAsync(client, "get_schema_info", new JsonObject
    {
        ["schema_name"] = Schema,
        ["table_name"] = Table,
    });
    var rows = ParseTsv(text);
    if (rows.Count == 0)
    {
        throw new McpException($"{Schema}.{Table} has no columns");
    }
    Console.WriteLine($"Columns of {Schema}.{Table}:");
    foreach (var row in rows)
    {
        var key = row.GetValueOrDefault("is_pk") == "true" ? " (primary key)" : "";
        Console.WriteLine($"- {row["column"]}: {row["data_type"]}{key}");
    }
}
// --8<-- [end:describe_table]

// --8<-- [start:count_rows]
// Counts the products in stock with count_rows. The where argument is a
// condition without the WHERE keyword; the server rejects one that
// contains a subquery.
static async Task CountInStockAsync(HttpClient client)
{
    var text = await CallToolAsync(client, "count_rows", new JsonObject
    {
        ["schema"] = Schema,
        ["table"] = Table,
        ["where"] = "in_stock",
    });
    // The reply ends with a line such as "Count: 4".
    var match = Regex.Match(text, @"^Count: (\d+)$", RegexOptions.Multiline);
    if (!match.Success)
    {
        throw new McpException($"The reply had no count: {Shorten(text)}");
    }
    Console.WriteLine($"Products in stock: {match.Groups[1].Value}");
}
// --8<-- [end:count_rows]

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
    await ListTablesAsync(client);
    await DescribeTableAsync(client);
    await CountInStockAsync(client);
}
// HttpRequestException covers failures to reach the server, such as a
// refused connection, and TaskCanceledException covers a timeout.
// KeyNotFoundException covers a row that lacks a column the program reads.
catch (Exception e) when (
    e is HttpRequestException or TaskCanceledException or McpException
        or KeyNotFoundException)
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
