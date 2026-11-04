/*
 * Ellie's Postgres Cookbook
 * Listening for notifications with LISTEN and NOTIFY, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
const string Channel = "cookbook_listen_notify";
var timeout = TimeSpan.FromSeconds(5);

// Returns the value of an environment variable, or null if the variable
// is unset or empty; libpq also treats an empty variable as unset.
static string? EnvValue(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : null;

// Returns the value of an environment variable, or a fallback if unset.
static string EnvOr(string name, string fallback) =>
    EnvValue(name) ?? fallback;

// Builds a connection string from the standard libpq environment
// variables, with defaults suitable for a local development server. The
// builder takes care of quoting any special characters.
static string ConnectionString() =>
    new NpgsqlConnectionStringBuilder
    {
        Host = EnvOr("PGHOST", "localhost"),
        Port = int.Parse(EnvOr("PGPORT", "5432")),
        Database = EnvOr("PGDATABASE", "postgres"),
        Username = EnvOr("PGUSER", "postgres"),
        Password = EnvValue("PGPASSWORD"),
    }.ConnectionString;
// --8<-- [end:config]

// --8<-- [start:connect]
// Creates a data source with the settings from the environment. A data
// source manages a pool of physical connections, and each call to
// OpenConnectionAsync borrows one from the pool, so the two calls below
// get two separate connections. Npgsql runs each command in autocommit
// mode unless the program starts a transaction, so LISTEN takes effect,
// and NOTIFY is delivered, as soon as the command completes.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:listen]
// Subscribes the connection to a channel.
static async Task ListenAsync(NpgsqlConnection conn, string channel)
{
    // LISTEN takes an identifier rather than a value, so it cannot use a
    // parameter; QuoteIdentifier quotes the name safely.
    await using var cmd = new NpgsqlCommand(
        $"LISTEN {new NpgsqlCommandBuilder().QuoteIdentifier(channel)}", conn);
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:listen]

// --8<-- [start:notify]
// Sends a notification to every connection listening on a channel.
static async Task NotifyAsync(
    NpgsqlConnection conn, string channel, string payload)
{
    // pg_notify() takes the channel and payload as ordinary parameters,
    // unlike the NOTIFY command. Positional parameters are written $1, $2,
    // and so on.
    await using var cmd = new NpgsqlCommand("SELECT pg_notify($1, $2)", conn)
    {
        Parameters = { new() { Value = channel }, new() { Value = payload } },
    };
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:notify]

// --8<-- [start:wait]
// Waits for a notification, and returns it, or null on timeout. Npgsql
// reads from the socket only while a command or WaitAsync is running, and
// raises the Notification event from there.
static async Task<NpgsqlNotificationEventArgs?> WaitForNotificationAsync(
    NpgsqlConnection conn, TimeSpan timeout)
{
    NpgsqlNotificationEventArgs? received = null;
    conn.Notification += (_, e) => received = e;

    using var cts = new CancellationTokenSource(timeout);
    try
    {
        // WaitAsync returns after any message from the server, so keep
        // waiting until the event has fired.
        while (received is null)
        {
            await conn.WaitAsync(cts.Token);
        }
    }
    catch (OperationCanceledException)
    {
        // The timeout passed with no notification.
    }
    return received;
}
// --8<-- [end:wait]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connections
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var listener = await dataSource.OpenConnectionAsync();
    await using var sender = await dataSource.OpenConnectionAsync();

    await ListenAsync(listener, Channel);
    Console.WriteLine($"Listening on channel '{Channel}'");

    await NotifyAsync(sender, Channel, "Hello from connection B");

    var message = await WaitForNotificationAsync(listener, timeout);
    if (message is null)
    {
        Console.Error.WriteLine(
            $"No notification within {timeout.TotalSeconds} seconds");
        return 1;
    }
    Console.WriteLine(
        $"Received notification on '{message.Channel}': {message.Payload}");
}
// NpgsqlException covers connection failures; PostgresException, which
// derives from it, carries errors reported by the server.
catch (NpgsqlException e)
{
    Console.Error.WriteLine($"Database error: {e.Message}");
    return 1;
}

return 0;
// --8<-- [end:main]
