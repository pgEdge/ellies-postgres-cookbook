/*
 * Ellie's Postgres Cookbook
 * Using transactions to move money between accounts, using libpq.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

/* --8<-- [start:imports] */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libpq-fe.h>
/* --8<-- [end:imports] */

/* --8<-- [start:config] */
/* Return the value of an environment variable, or a fallback if unset. */
static const char *
env_or(const char *name, const char *fallback)
{
    const char *value = getenv(name);

    return (value != NULL && value[0] != '\0') ? value : fallback;
}

/*
 * Connection parameters are passed to libpq as two parallel,
 * NULL-terminated arrays of keywords and values. A NULL value is ignored,
 * so the password is only sent if PGPASSWORD is set.
 */
static const char *const keywords[] = {
    "host", "port", "dbname", "user", "password", NULL
};

/* Fill in the value for each keyword from the environment. */
static void
read_settings(const char *values[])
{
    values[0] = env_or("PGHOST", "localhost");
    values[1] = env_or("PGPORT", "5432");
    values[2] = env_or("PGDATABASE", "postgres");
    values[3] = env_or("PGUSER", "postgres");
    values[4] = env_or("PGPASSWORD", NULL);
    values[5] = NULL;
}
/* --8<-- [end:config] */

/* --8<-- [start:connect] */
/*
 * Open a connection with the settings from the environment. libpq always
 * returns a connection object, which the caller must check with PQstatus()
 * and release with PQfinish(), even if the connection attempt failed.
 */
static PGconn *
connect_to_server(void)
{
    const char *values[sizeof(keywords) / sizeof(keywords[0])];

    read_settings(values);
    return PQconnectdbParams(keywords, values, 0);
}
/* --8<-- [end:connect] */

/* --8<-- [start:setup] */
/*
 * Create a temporary table of two accounts, and return true on success.
 * The CHECK constraint stops any balance from going below zero. PQexec()
 * runs both statements, which need no parameters, in a single call.
 */
static bool
create_accounts(PGconn *conn)
{
    PGresult *res = PQexec(conn,
                           "CREATE TEMPORARY TABLE accounts ("
                           "id int PRIMARY KEY, "
                           "balance int NOT NULL CHECK (balance >= 0)); "
                           "INSERT INTO accounts VALUES (1, 100), (2, 50)");
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

    PQclear(res);
    return ok;
}
/* --8<-- [end:setup] */

/* --8<-- [start:transfer] */
/* The SQLSTATE and message of the statement that failed. */
typedef struct
{
    char sqlstate[6];
    char message[256];
} Failure;

/*
 * Run one statement with the given text parameters, and return true on
 * success. On failure, store the SQLSTATE and the message in *failure,
 * because the next command on the connection overwrites them.
 */
static bool
run_statement(PGconn *conn, const char *sql, int nparams,
              const char *const *params, Failure *failure)
{
    PGresult *res = PQexecParams(conn, sql, nparams, NULL, params,
                                 NULL, NULL, 0);
    ExecStatusType status = PQresultStatus(res);
    bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;

    if (!ok)
    {
        const char *state = PQresultErrorField(res, PG_DIAG_SQLSTATE);

        /* Connection failures carry no SQLSTATE, so store an empty one. */
        snprintf(failure->sqlstate, sizeof(failure->sqlstate), "%s",
                 state != NULL ? state : "");
        snprintf(failure->message, sizeof(failure->message), "%s",
                 PQerrorMessage(conn));
    }
    PQclear(res);
    return ok;
}

/*
 * Move money between two accounts in a single transaction, and return
 * true on success. On failure, the transaction has been rolled back and
 * *failure says why.
 */
static bool
transfer(PGconn *conn, int source, int target, int amount,
         Failure *failure)
{
    char amount_text[16], source_text[16], target_text[16];
    const char *credit[2] = {amount_text, target_text};
    const char *debit[2] = {amount_text, source_text};
    bool ok;

    snprintf(amount_text, sizeof(amount_text), "%d", amount);
    snprintf(source_text, sizeof(source_text), "%d", source);
    snprintf(target_text, sizeof(target_text), "%d", target);

    /*
     * libpq has no transaction object, so the program sends BEGIN, COMMIT,
     * and ROLLBACK itself. Credit the target first, so that a failure of
     * the debit shows that the rollback undoes the credit as well.
     */
    ok = run_statement(conn, "BEGIN", 0, NULL, failure) &&
         run_statement(conn,
                       "UPDATE accounts SET balance = balance + $1 "
                       "WHERE id = $2", 2, credit, failure) &&
         run_statement(conn,
                       "UPDATE accounts SET balance = balance - $1 "
                       "WHERE id = $2", 2, debit, failure);

    if (ok)
        return run_statement(conn, "COMMIT", 0, NULL, failure);

    /*
     * Roll back, but keep the original failure. A ROLLBACK sent when BEGIN
     * itself failed does no harm, so no special case is needed.
     */
    PQclear(PQexec(conn, "ROLLBACK"));
    return false;
}
/* --8<-- [end:transfer] */

/* --8<-- [start:balance] */
/*
 * Store the balance of the given account in *balance, and return true on
 * success. On failure, PQerrorMessage() describes the error.
 */
static bool
get_balance(PGconn *conn, int account, int *balance)
{
    char account_text[16];
    const char *params[] = {account_text};
    PGresult *res;
    bool ok;

    snprintf(account_text, sizeof(account_text), "%d", account);
    res = PQexecParams(conn, "SELECT balance FROM accounts WHERE id = $1",
                       1, NULL, params, NULL, NULL, 0);
    ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    /* Results arrive as text, so convert the value to a number. */
    if (ok)
        *balance = atoi(PQgetvalue(res, 0, 0));

    PQclear(res);
    return ok;
}
/* --8<-- [end:balance] */

/* --8<-- [start:main] */
/*
 * Make the transfers and print the balances, and return true on success.
 * On failure, *failure holds the message to report.
 */
static bool
run_example(PGconn *conn, Failure *failure)
{
    int account, balance;

    if (!create_accounts(conn))
    {
        snprintf(failure->message, sizeof(failure->message), "%s",
                 PQerrorMessage(conn));
        return false;
    }

    if (!transfer(conn, 1, 2, 30, failure))
        return false;
    printf("Transferred 30 from account 1 to account 2\n");

    /*
     * SQLSTATE 23514 is a check constraint violation. The transaction has
     * already been rolled back, so this is an expected outcome; any other
     * error is not, and is reported as a failure.
     */
    if (transfer(conn, 1, 2, 500, failure))
        printf("Transferred 500 from account 1 to account 2\n");
    else if (strcmp(failure->sqlstate, "23514") == 0)
        printf("Transfer of 500 from account 1 to account 2 "
               "failed and was rolled back\n");
    else
        return false;

    for (account = 1; account <= 2; account++)
    {
        if (!get_balance(conn, account, &balance))
        {
            snprintf(failure->message, sizeof(failure->message), "%s",
                     PQerrorMessage(conn));
            return false;
        }
        printf("Account %d balance: %d\n", account, balance);
    }
    return true;
}

int
main(void)
{
    int status = EXIT_FAILURE;
    Failure failure = {"", ""};
    PGconn *conn = connect_to_server();

    if (PQstatus(conn) != CONNECTION_OK)
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    else if (!run_example(conn, &failure))
        fprintf(stderr, "Database error: %s", failure.message);
    else
        status = EXIT_SUCCESS;

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
