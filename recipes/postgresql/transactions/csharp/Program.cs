/*
 * Ellie's Postgres Cookbook
 * Using transactions to move money between accounts, using Npgsql.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
using Npgsql;
// --8<-- [end:imports]

// --8<-- [start:config]
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
// OpenConnectionAsync borrows one from the pool; an application normally
// creates one data source at start-up and shares it. A temporary table
// belongs to one physical connection, so this program borrows a single
// connection and uses it throughout.
static NpgsqlDataSource CreateDataSource() =>
    NpgsqlDataSource.Create(ConnectionString());
// --8<-- [end:connect]

// --8<-- [start:setup]
// Creates a temporary table of two accounts. The CHECK constraint stops
// any balance from going below zero.
static async Task CreateAccountsAsync(NpgsqlConnection conn)
{
    await using var cmd = new NpgsqlCommand(
        "CREATE TEMPORARY TABLE accounts (" +
        "id int PRIMARY KEY, " +
        "balance int NOT NULL CHECK (balance >= 0)); " +
        "INSERT INTO accounts VALUES (1, 100), (2, 50)", conn);
    await cmd.ExecuteNonQueryAsync();
}
// --8<-- [end:setup]

// --8<-- [start:transfer]
// Moves money between two accounts in a single transaction.
static async Task TransferAsync(
    NpgsqlConnection conn, int source, int target, int amount)
{
    // BeginTransactionAsync sends BEGIN. Disposing of the transaction
    // without committing it rolls the transaction back, so an exception
    // thrown below undoes the work.
    await using var tx = await conn.BeginTransactionAsync();

    // Credit the target first, so that a failure of the debit shows that
    // the rollback undoes the credit as well. Positional parameters are
    // written $1, $2, and so on.
    await using (var credit = new NpgsqlCommand(
        "UPDATE accounts SET balance = balance + $1 WHERE id = $2", conn, tx)
    {
        Parameters = { new() { Value = amount }, new() { Value = target } },
    })
    {
        await credit.ExecuteNonQueryAsync();
    }

    await using (var debit = new NpgsqlCommand(
        "UPDATE accounts SET balance = balance - $1 WHERE id = $2", conn, tx)
    {
        Parameters = { new() { Value = amount }, new() { Value = source } },
    })
    {
        await debit.ExecuteNonQueryAsync();
    }

    await tx.CommitAsync();
}
// --8<-- [end:transfer]

// --8<-- [start:balance]
// Returns the balance of the given account.
static async Task<int> GetBalanceAsync(NpgsqlConnection conn, int account)
{
    await using var cmd = new NpgsqlCommand(
        "SELECT balance FROM accounts WHERE id = $1", conn)
    {
        Parameters = { new() { Value = account } },
    };

    // ExecuteScalarAsync returns the first column of the first row. An
    // int maps to int.
    return (int)(await cmd.ExecuteScalarAsync())!;
}
// --8<-- [end:balance]

// --8<-- [start:main]
try
{
    // await using disposes of the data source, and returns the connection
    // to the pool, when the block exits, whether or not an error occurred.
    await using var dataSource = CreateDataSource();
    await using var conn = await dataSource.OpenConnectionAsync();

    await CreateAccountsAsync(conn);

    await TransferAsync(conn, 1, 2, 30);
    Console.WriteLine("Transferred 30 from account 1 to account 2");

    try
    {
        await TransferAsync(conn, 1, 2, 500);
        Console.WriteLine("Transferred 500 from account 1 to account 2");
    }
    // SQLSTATE 23514 is a check constraint violation. The transaction has
    // already been rolled back, so this is an expected outcome; any other
    // error is not, and reaches the handler below.
    catch (PostgresException e) when (
        e.SqlState == PostgresErrorCodes.CheckViolation)
    {
        Console.WriteLine(
            "Transfer of 500 from account 1 to account 2 " +
            "failed and was rolled back");
    }

    foreach (var account in new[] { 1, 2 })
    {
        Console.WriteLine(
            $"Account {account} balance: {await GetBalanceAsync(conn, account)}");
    }
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
