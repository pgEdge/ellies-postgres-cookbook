/*
 * Ellie's Postgres Cookbook
 * Creating a branch of a pgEdge Starfleet database for a test run, and
 * connecting to it, using HttpClient, System.Text.Json, and Npgsql.
 *
 * The program creates a database of its own to branch. The Starfleet
 * service bills for every database and every branch from the moment that it
 * becomes connectable, so the program deletes the branch and then the
 * database on every path: after a success, after a failure, and after
 * Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const int TimeoutSeconds = 900;
const int PollSeconds = 10;

// How many times to look for a database whose create reply was lost.
const int LookupAttempts = 3;

// How many times to try connecting to the database before giving up.
const int ConnectAttempts = 6;

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

// Returns a deadline the given number of seconds from now, and reports
// whether it is still in the future, on a clock that only moves forwards.
static long Deadline(int seconds) => Environment.TickCount64 + seconds * 1000L;
static bool Before(long deadline) => Environment.TickCount64 < deadline;

// A token that SIGINT or SIGTERM cancels, which abandons the request or
// the wait in progress. The clean-up replaces it with CancellationToken.None,
// so that nothing can cut the clean-up short.
using var signalled = new CancellationTokenSource();
var cancel = signalled.Token;

// Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
// which would end the program before it could delete the database, and a
// second signal does nothing more.
void OnSignal(PosixSignalContext context)
{
    context.Cancel = true;
    signalled.Cancel();
}
using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);

// Waits for the given number of seconds; a signal ends the wait early.
async Task Pause(int seconds) =>
    await Task.Delay(TimeSpan.FromSeconds(seconds), cancel);
// --8<-- [end:config]

// --8<-- [start:token]
// One client serves every request. Its timeout covers the whole exchange,
// the body of the reply included.
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

// Sends a request with a JSON body, if there is one, and returns the
// decoded JSON reply, or null if the reply has no body. A 4xx or 5xx reply
// throws an HttpRequestException that carries the status.
async Task<JsonNode?> Request(string method, string url, string path,
    string? token, object? body, CancellationToken cancelRequest)
{
    using var request = new HttpRequestMessage(new HttpMethod(method), url);
    if (token is not null)
    {
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    }
    if (body is not null)
    {
        // StringContent sends a Content-Length header; JsonContent would
        // stream the body in chunks, which not every server accepts.
        request.Content = new StringContent(
            JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
    }

    using var response = await http.SendAsync(request, cancelRequest);
    var text = await response.Content.ReadAsStringAsync(cancelRequest);
    if ((int)response.StatusCode >= 400)
    {
        throw new HttpRequestException(
            $"{method} {path} failed with status {(int)response.StatusCode}: "
            + text.Trim(), null, response.StatusCode);
    }
    return text.Length == 0 ? null : JsonNode.Parse(text);
}

// Returns a field of a JSON object as text, and throws if the field is
// missing.
static string Field(JsonNode? node, string name) =>
    node?[name] is JsonNode value
        ? value.ToString()
        : throw new InvalidOperationException($"the reply has no {name}");

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
    var token = await Request("POST", cfg.BaseUrl + path, path, null, new
    {
        grant_type = "client_credentials",
        client_id = cfg.ClientId,
        client_secret = cfg.ClientSecret,
    }, cancel);
    return Field(token, "access_token");
}
// --8<-- [end:token]

// --8<-- [start:api]
// Sends an authenticated request to the Managed API and returns the
// decoded JSON reply, or null if the reply has no body. The create call
// passes interruptible: false, so that a signal cannot abandon a request
// whose result the program must not lose.
async Task<JsonNode?> Api(string token, string method, string path,
    object? body = null, bool interruptible = true) =>
    await Request(method, $"{cfg.BaseUrl}/managed/v1{path}", path, token,
        body, interruptible ? cancel : CancellationToken.None);
// --8<-- [end:api]

// --8<-- [start:placement]
// Returns the region and size for the new database. The API lists sizes
// smallest first, so the first one is the cheapest. The API does not price
// regions, so the example takes the first one.
async Task<(string Region, string Size)> ChoosePlacement(string token)
{
    var regions = await Api(token, "GET", "/regions") as JsonArray;
    var sizes = await Api(token, "GET", "/sizes") as JsonArray;
    if (regions is not { Count: > 0 } || sizes is not { Count: > 0 })
    {
        throw new InvalidOperationException("the API offers no region or size");
    }
    return (Field(regions[0], "region"), Field(sizes[0], "name"));
}
// --8<-- [end:placement]

// --8<-- [start:create]
// Returns the address that the API sees requests come from.
async Task<string> ClientIp(string token)
{
    // A new database is closed to everyone until an allowlist rule admits
    // an address. The API reports the address it sees this request come
    // from, which is the one to admit; a bare address means a single host.
    return Field(await Api(token, "GET", "/client-ip"), "ip_address");
}

// Creates a database that only this machine can reach, and returns the
// API's description of it, which includes its ID.
async Task<JsonNode?> CreateDatabase(string token, string name,
    string displayName, string region, string size, string ip) =>
    await Api(token, "POST", "/databases", new
    {
        // The name becomes the Postgres database name, so it holds only
        // letters and digits, and the readable cookbook- prefix goes in the
        // display name. The program also uses the name to find the
        // database again if the reply to this request is lost.
        name,
        display_name = displayName,
        region,
        size,
        ip_allowlist = new
        {
            rules = new[] { new { cidr = ip, label = "cookbook" } },
        },
    }, interruptible: false);
// --8<-- [end:create]

// --8<-- [start:wait]
// The API does not document its status values; the example treats these
// two as failures, which end the wait at once instead of leaving it to run
// until the time limit.
string[] failedStatuses = ["degraded", "failed"];

// Polls the database until its status is available.
async Task WaitUntilAvailable(string token, string databaseId)
{
    var deadline = Deadline(TimeoutSeconds);
    string? last = null;
    while (Before(deadline))
    {
        var status = Field(
            await Api(token, "GET", $"/databases/{databaseId}"), "status");
        if (status != last)
        {
            Console.WriteLine($"Database status: {status}");
            last = status;
        }
        if (status == "available")
        {
            return;
        }
        if (failedStatuses.Contains(status))
        {
            throw new InvalidOperationException(
                $"the database has the status {status}");
        }
        await Pause(PollSeconds);
    }
    throw new InvalidOperationException(
        $"the database was not available after {TimeoutSeconds} seconds");
}
// --8<-- [end:wait]

// --8<-- [start:branch]
// Creates a copy-on-write branch of the database, and returns the API's
// description of it, which includes its ID.
async Task<JsonNode?> CreateBranch(string token, string databaseId,
    string displayName)
{
    // The API assigns the name of a branch, so the program gives the branch
    // a display name and uses that to find it again if the reply to this
    // request is lost. The request sets no allowlist, so the branch copies
    // the rules of the database, which admit this machine. The branch also
    // copies the size, the region, and the Postgres version.
    return await Api(token, "POST", $"/databases/{databaseId}/branches",
        new { display_name = displayName }, interruptible: false);
}

// Polls the branch until its status is available.
async Task WaitUntilBranchAvailable(string token, string branchPath)
{
    var deadline = Deadline(TimeoutSeconds);
    string? last = null;
    while (Before(deadline))
    {
        var status = Field(await Api(token, "GET", branchPath), "status");
        if (status != last)
        {
            Console.WriteLine($"Branch status: {status}");
            last = status;
        }
        if (status == "available")
        {
            return;
        }
        if (failedStatuses.Contains(status))
        {
            throw new InvalidOperationException(
                $"the branch has the status {status}");
        }
        await Pause(PollSeconds);
    }
    throw new InvalidOperationException(
        $"the branch was not available after {TimeoutSeconds} seconds");
}
// --8<-- [end:branch]

// --8<-- [start:connection]
// Reads the connection details of an available branch, and returns them
// as Npgsql connection settings.
async Task<NpgsqlConnectionStringBuilder> ConnectionSettings(string token,
    string branchPath)
{
    // The connection details, including the password of the branch's own
    // application user, come with the description of the branch. They are
    // present only while the branch is available. The API does not require
    // the host, so fall back to the external IP address if it is missing.
    var connection = (await Api(token, "GET", branchPath))?["connection"];
    string? Value(string key) =>
        connection?[key]?.ToString() is { Length: > 0 } value ? value : null;
    var host = Value("host") ?? Value("external_ip_address");
    var port = Value("port");
    var database = Value("database");
    var user = Value("username");
    var password = Value("password");
    if (host is null || port is null || database is null || user is null
        || password is null)
    {
        throw new InvalidOperationException(
            "the database description has incomplete connection details");
    }
    return new NpgsqlConnectionStringBuilder
    {
        Host = host,
        Port = int.Parse(port, CultureInfo.InvariantCulture),
        Database = database,
        Username = user,
        Password = password,
        // Encrypt the connection. The certificate of a Starfleet database
        // is not signed by a public authority, so the example does not
        // verify it; Npgsql checks no certificate in Require mode.
        SslMode = SslMode.Require,
        // The connection timeout, in seconds.
        Timeout = 15,
    };
}
// --8<-- [end:connection]

// --8<-- [start:query]
// Connects to the database and returns the result of a query that returns
// one text value.
async Task<string> QueryOne(NpgsqlConnectionStringBuilder settings, string sql)
{
    // A database can refuse connections for a short while after the API
    // reports it as available, so try a few times before giving up. A
    // PostgresException carries an SQLSTATE code: it came from the server
    // itself, such as a failed login, and will not change on a second
    // attempt.
    for (var attempt = 0; ; attempt++)
    {
        try
        {
            // The using declarations close the connection when the block
            // exits, whether or not an error occurred.
            await using var conn = new NpgsqlConnection(settings.ConnectionString);
            await conn.OpenAsync(cancel);
            await using var command = new NpgsqlCommand(sql, conn);
            return (string)(await command.ExecuteScalarAsync(cancel))!;
        }
        catch (NpgsqlException e) when (e is not PostgresException
            && attempt < ConnectAttempts - 1)
        {
            await Pause(PollSeconds);
        }
    }
}
// --8<-- [end:query]

// --8<-- [start:delete]
// Reports whether a failed request is worth repeating: no reply arrived,
// such as a refused connection or a timeout, the service is overloaded or
// failing, or it answered 409, which the API does whilst a database is
// still being created.
static bool IsTransient(Exception e) => e switch
{
    HttpRequestException { StatusCode: HttpStatusCode code } =>
        (int)code is 409 or 429 or >= 500,
    HttpRequestException or TaskCanceledException => true,
    _ => false,
};

// Reports whether an error is a 404 reply, which means that the database
// does not exist.
static bool IsGone(Exception e) =>
    e is HttpRequestException { StatusCode: HttpStatusCode.NotFound };

// Returns the ID of the database with the given name, or null. The program
// uses this when it cannot tell whether a create request worked. It
// repeats the request, as the delete does, because the fault that lost the
// reply to the create request may still be there. The request asks for
// the newest databases first, but the API does not say which property it
// sorts on.
async Task<string?> FindDatabase(string token, string name)
{
    var deadline = Deadline(TimeoutSeconds);
    JsonNode? databases;
    while (true)
    {
        try
        {
            databases = await Api(
                token, "GET", "/databases?limit=100&descending=true");
            break;
        }
        catch (Exception e) when (IsTransient(e) && Before(deadline))
        {
            await Pause(PollSeconds);
        }
    }
    foreach (var database in databases as JsonArray ?? [])
    {
        if (database?["name"]?.ToString() == name)
        {
            return Field(database, "id");
        }
    }
    return null;
}

// Looks for the database a few times, because the service may not have
// recorded a request whose reply was lost until a little later. Returns
// null if the database never appears.
async Task<string?> FindCreatedDatabase(string token, string name)
{
    for (var attempt = 0; attempt < LookupAttempts; attempt++)
    {
        if (await FindDatabase(token, name) is string databaseId)
        {
            return databaseId;
        }
        if (attempt < LookupAttempts - 1)
        {
            await Pause(PollSeconds);
        }
    }
    return null;
}

// Reports whether a failed create request might still have created the
// database: no reply arrived, the reply could not be read, or the service
// failed with a 5xx status. A 4xx reply is a definite refusal.
static bool OutcomeUnknown(Exception e) =>
    e is not HttpRequestException { StatusCode: HttpStatusCode code }
        || (int)code >= 500;

// Returns the branches of the database that have not been deleted, newest
// first. The request repeats, as the deletes do, and a 404 means that the
// database has gone, and so have its branches.
async Task<JsonArray> ListBranches(string token, string databaseId)
{
    var deadline = Deadline(TimeoutSeconds);
    while (true)
    {
        try
        {
            return await Api(token, "GET",
                $"/databases/{databaseId}/branches?limit=100&descending=true")
                as JsonArray ?? [];
        }
        catch (Exception e) when (IsGone(e))
        {
            return [];
        }
        catch (Exception e) when (IsTransient(e) && Before(deadline))
        {
            await Pause(PollSeconds);
        }
    }
}

// Looks for the branch with the given display name a few times, because the
// service may not have recorded a request whose reply was lost until a
// little later. Returns null if the branch never appears.
async Task<string?> FindCreatedBranch(string token, string databaseId,
    string displayName)
{
    for (var attempt = 0; attempt < LookupAttempts; attempt++)
    {
        foreach (var branch in await ListBranches(token, databaseId))
        {
            if (branch?["display_name"]?.ToString() == displayName)
            {
                return Field(branch, "id");
            }
        }
        if (attempt < LookupAttempts - 1)
        {
            await Pause(PollSeconds);
        }
    }
    return null;
}

// Deletes the branch and waits until the API no longer lists it.
async Task DeleteBranch(string token, string databaseId, string branchId)
{
    var deadline = Deadline(TimeoutSeconds);
    while (true)
    {
        try
        {
            await Api(token, "DELETE",
                $"/databases/{databaseId}/branches/{branchId}");
            break;
        }
        catch (Exception e) when (IsGone(e))
        {
            return;
        }
        catch (Exception e) when (IsTransient(e) && Before(deadline))
        {
            await Pause(PollSeconds);
        }
    }

    // The API takes a branch out of the list as soon as it accepts the
    // delete, even though the teardown carries on afterwards.
    while (Before(deadline))
    {
        var branches = await ListBranches(token, databaseId);
        if (branches.All(branch => Field(branch, "id") != branchId))
        {
            return;
        }
        await Pause(PollSeconds);
    }
    throw new InvalidOperationException(
        $"the branch was still listed after {TimeoutSeconds} seconds");
}

// Deletes the database and waits until the API no longer lists it.
async Task DeleteDatabase(string token, string databaseId)
{
    var deadline = Deadline(TimeoutSeconds);
    while (true)
    {
        try
        {
            // The API refuses to delete a database that has branches,
            // with a 409 reply, unless force=true, which deletes every
            // branch first. The program has deleted its branch by now, so
            // this is a safety net for a branch that the program could not
            // find.
            await Api(token, "DELETE", $"/databases/{databaseId}?force=true");
            break;
        }
        catch (Exception e) when (IsGone(e))
        {
            return;
        }
        catch (Exception e) when (IsTransient(e) && Before(deadline))
        {
            await Pause(PollSeconds);
        }
    }

    // The delete starts the teardown; a 404 shows that it has finished.
    while (Before(deadline))
    {
        try
        {
            await Api(token, "GET", $"/databases/{databaseId}");
        }
        catch (Exception e) when (IsGone(e))
        {
            return;
        }
        catch (Exception e) when (IsTransient(e))
        {
        }
        await Pause(PollSeconds);
    }
    throw new InvalidOperationException(
        $"the database was still present after {TimeoutSeconds} seconds");
}
// --8<-- [end:delete]

// --8<-- [start:main]
// Reports whether an error is one that the program expects: a failure to
// connect, an error reply from the API, a request that timed out, a reply
// that is not JSON, a reply that the program cannot use, or any error from
// Npgsql, whose PostgresException carries an error from the server.
static bool Expected(Exception e) => e is HttpRequestException
    or TaskCanceledException or JsonException or InvalidOperationException
    or NpgsqlException;

string? token = null;
string? name = null;
string? databaseId = null;
var lookup = false;
string? branchId = null;
string? branchName = null;
var branchLookup = false;
var exitCode = 0;
try
{
    token = await GetToken();

    var (region, size) = await ChoosePlacement(token);
    Console.WriteLine($"Region: {region}");
    Console.WriteLine($"Size: {size}");

    // Choose the name before the request, so that the program can find the
    // database even if the reply to the request never arrives.
    var suffix = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3));
    name = $"cookbook{suffix}";
    var displayName = $"cookbook-{suffix}";
    // Look the database up by name afterwards only if the outcome of the
    // request is unknown, so that a refusal cannot lead the clean-up to
    // delete another database that has the same name.
    var ip = await ClientIp(token);
    lookup = true;
    JsonNode? database;
    try
    {
        database = await CreateDatabase(token, name, displayName, region, size, ip);
    }
    catch (Exception e) when (Expected(e))
    {
        lookup = OutcomeUnknown(e);
        throw;
    }
    databaseId = Field(database, "id");
    Console.WriteLine($"Created database {Field(database, "display_name")}");

    await WaitUntilAvailable(token, databaseId);
    Console.WriteLine("Database is available");

    // The program names the branch before the request, as it does the
    // database, and looks it up afterwards only if the outcome is unknown.
    branchName = $"cookbook-{suffix}-branch";
    branchLookup = true;
    JsonNode? branch;
    try
    {
        branch = await CreateBranch(token, databaseId, branchName);
    }
    catch (Exception e) when (Expected(e))
    {
        branchLookup = OutcomeUnknown(e);
        throw;
    }
    branchId = Field(branch, "id");
    Console.WriteLine($"Created branch {Field(branch, "display_name")}");

    var branchPath = $"/databases/{databaseId}/branches/{branchId}";
    await WaitUntilBranchAvailable(token, branchPath);
    Console.WriteLine("Branch is available");

    var connection = await ConnectionSettings(token, branchPath);
    Console.WriteLine("Branch server version: "
        + await QueryOne(connection, "SELECT version()"));
}
// After a signal, the request or wait in progress fails, whatever the
// error that it reports.
catch (Exception) when (signalled.IsCancellationRequested)
{
    Console.Error.WriteLine("Interrupted");
    exitCode = 130;
}
catch (Exception e) when (Expected(e))
{
    Console.Error.WriteLine($"Error: {e.Message}");
    exitCode = 1;
}
finally
{
    // Delete the database whether the example succeeded, failed, or was
    // interrupted, because the service bills for it until then. Signals
    // no longer cancel anything, so that they cannot cut the clean-up
    // short. The finally block also runs for an error that the catch does
    // not handle.
    cancel = CancellationToken.None;
    if (token is not null && name is not null)
    {
        try
        {
            if (databaseId is null && lookup)
            {
                databaseId = await FindCreatedDatabase(token, name);
                if (databaseId is null)
                {
                    Console.Error.WriteLine(
                        $"Error: the database {name} was not found; "
                        + "check your account for it by hand");
                    exitCode = 1;
                }
            }
            if (databaseId is not null)
            {
                // Delete the branch before the database. A failure here must
                // not stop the database delete, which uses force=true as a
                // safety net.
                try
                {
                    if (branchId is null && branchLookup)
                    {
                        branchId = await FindCreatedBranch(
                            token, databaseId, branchName!);
                        if (branchId is null)
                        {
                            Console.Error.WriteLine(
                                $"Error: the branch {branchName} was not found; "
                                + "check your account for it by hand");
                            exitCode = 1;
                        }
                    }
                    if (branchId is not null)
                    {
                        await DeleteBranch(token, databaseId, branchId);
                        Console.WriteLine("Deleted branch");
                    }
                }
                catch (Exception e) when (Expected(e))
                {
                    Console.Error.WriteLine($"Error: {e.Message}");
                    Console.Error.WriteLine(
                        "The forced delete of the database that follows "
                        + "also deletes the branch");
                    exitCode = 1;
                }
                await DeleteDatabase(token, databaseId);
                Console.WriteLine("Deleted database");
            }
        }
        catch (Exception e) when (Expected(e))
        {
            Console.Error.WriteLine($"Error: {e.Message}");
            Console.Error.WriteLine(
                $"Delete the database {databaseId ?? name} and any "
                + "branches by hand, because it may still be billing");
            exitCode = 1;
        }
    }
}

return exitCode;
// --8<-- [end:main]
