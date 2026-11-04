/*
 * Ellie's Postgres Cookbook
 * Setting a server-side statement timeout, using libpq.
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
/*
 * The SQLSTATE code that the server reports when it cancels a statement,
 * whether because of a timeout or because a client asked for the cancel.
 */
#define QUERY_CANCELED "57014"

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
 * and release with PQfinish(), even if the connection attempt failed. The
 * server runs each statement in its own transaction unless the program
 * sends BEGIN, so a cancelled statement does not leave the session in a
 * failed transaction.
 */
static PGconn *
connect_to_server(void)
{
    const char *values[sizeof(keywords) / sizeof(keywords[0])];

    read_settings(values);
    return PQconnectdbParams(keywords, values, 0);
}
/* --8<-- [end:connect] */

/* --8<-- [start:timeout] */
/*
 * Set the statement timeout for the rest of the session, and return true
 * on success.
 */
static bool
set_statement_timeout(PGconn *conn, const char *timeout)
{
    /*
     * SET cannot take a parameter, but set_config() is an ordinary
     * function, so the value can be sent safely. The final argument,
     * false, makes the setting last for the session rather than for the
     * current transaction.
     */
    const char *params[] = {timeout};
    PGresult *res = PQexecParams(conn,
                                 "SELECT set_config('statement_timeout', "
                                 "$1, false)",
                                 1, NULL, params, NULL, NULL, 0);
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    PQclear(res);
    return ok;
}

/*
 * Run a statement that outlasts the timeout. Return true if the statement
 * was cancelled, which is the expected outcome. Return false for any other
 * result, in which case *failed is set if the statement raised an error.
 */
static bool
sleep_exceeds_timeout(PGconn *conn, bool *failed)
{
    PGresult *res = PQexec(conn, "SELECT pg_sleep(5)");
    const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);
    bool cancelled = code != NULL && strcmp(code, QUERY_CANCELED) == 0;

    /*
     * Only a cancelled statement is expected here; any other error is a
     * real failure, which the caller reports.
     */
    *failed = PQresultStatus(res) != PGRES_TUPLES_OK && !cancelled;

    PQclear(res);
    return cancelled;
}

/* Return true if the session can still run a statement. */
static bool
is_usable(PGconn *conn)
{
    PGresult *res = PQexec(conn, "SELECT 1");
    bool usable = PQresultStatus(res) == PGRES_TUPLES_OK &&
        strcmp(PQgetvalue(res, 0, 0), "1") == 0;

    PQclear(res);
    return usable;
}
/* --8<-- [end:timeout] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    bool failed;
    PGconn *conn = connect_to_server();

    if (PQstatus(conn) != CONNECTION_OK ||
        !set_statement_timeout(conn, "100ms"))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        if (sleep_exceeds_timeout(conn, &failed))
            printf("Query cancelled after exceeding the statement "
                   "timeout\n");

        if (failed)
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        else
        {
            printf("Connection still usable: %s\n",
                   is_usable(conn) ? "true" : "false");
            status = EXIT_SUCCESS;
        }
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
