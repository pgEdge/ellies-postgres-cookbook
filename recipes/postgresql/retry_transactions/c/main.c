/*
 * Ellie's Postgres Cookbook
 * Retrying a transaction after a serialisation failure, using libpq.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

/* --8<-- [start:imports] */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libpq-fe.h>
/* --8<-- [end:imports] */

/* --8<-- [start:config] */
#define MAX_ATTEMPTS 5

/*
 * Return true if a SQLSTATE code means "run the transaction again": 40001
 * is a serialisation failure and 40P01 is a deadlock.
 */
static bool
is_retryable(const char *sqlstate)
{
    return strcmp(sqlstate, "40001") == 0 || strcmp(sqlstate, "40P01") == 0;
}

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
 * sends BEGIN, so the program decides where each transaction starts and
 * ends.
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
 * Run a statement with optional text parameters, and return true if it
 * succeeded. The five-character SQLSTATE code of a failure is copied into
 * sqlstate, which is empty if the statement succeeded or the failure has
 * no code (for example, a lost connection). If value is not NULL, the
 * first column of the first row is copied into it, up to size bytes.
 */
static bool
run_sql(PGconn *conn, const char *sql, int nparams, const char *const *params,
        char *sqlstate, char *value, size_t size)
{
    PGresult *res = PQexecParams(conn, sql, nparams, NULL, params, NULL,
                                 NULL, 0);
    ExecStatusType status = PQresultStatus(res);
    bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
    const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);

    snprintf(sqlstate, 6, "%s", code != NULL ? code : "");
    if (ok && value != NULL)
        snprintf(value, size, "%s", PQgetvalue(res, 0, 0));

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    return ok;
}

/* Drop the shared counter table if it exists. */
static bool
drop_table(PGconn *conn)
{
    char sqlstate[6];

    return run_sql(conn, "DROP TABLE IF EXISTS cookbook_retry_transactions",
                   0, NULL, sqlstate, NULL, 0);
}

/*
 * Create the shared counter table, with a single row set to zero. The
 * table must be visible to a second connection, so it cannot be
 * temporary; the name is specific to this recipe, and any earlier copy is
 * dropped first.
 */
static bool
create_table(PGconn *conn)
{
    const char *params[] = {"1", "0"};
    char sqlstate[6];

    return drop_table(conn) &&
        run_sql(conn,
                "CREATE TABLE cookbook_retry_transactions "
                "(id int PRIMARY KEY, value int NOT NULL)",
                0, NULL, sqlstate, NULL, 0) &&
        run_sql(conn,
                "INSERT INTO cookbook_retry_transactions (id, value) "
                "VALUES ($1, $2)",
                2, params, sqlstate, NULL, 0);
}
/* --8<-- [end:setup] */

/* --8<-- [start:work] */
/* Read the current value of the counter into *counter. */
static bool
read_counter(PGconn *conn, int *counter, char *sqlstate)
{
    const char *params[] = {"1"};
    char text[32];

    if (!run_sql(conn,
                 "SELECT value FROM cookbook_retry_transactions "
                 "WHERE id = $1",
                 1, params, sqlstate, text, sizeof(text)))
        return false;

    /* Results arrive as text, so convert the value to a number. */
    *counter = atoi(text);
    return true;
}

/*
 * Simulate another client by incrementing the counter on a second
 * connection, which commits straight away because it has no open
 * transaction. On failure, the SQLSTATE code and error message of the
 * second connection are copied into the caller's buffers.
 */
static bool
update_from_other_connection(char *sqlstate, char *message, size_t size)
{
    const char *params[] = {"1"};
    PGconn *other = connect_to_server();
    bool ok = PQstatus(other) == CONNECTION_OK &&
        run_sql(other,
                "UPDATE cookbook_retry_transactions SET value = value + 1 "
                "WHERE id = $1",
                1, params, sqlstate, NULL, 0);

    if (!ok)
        snprintf(message, size, "%s", PQerrorMessage(other));
    PQfinish(other);
    return ok;
}

/*
 * Read the counter and write back the value plus one. A failure on conn
 * leaves message empty, because PQerrorMessage(conn) describes it.
 */
static bool
increment_counter(PGconn *conn, int attempt, char *sqlstate,
                  char *message, size_t size)
{
    int counter;
    char next[32];
    const char *params[2];

    if (!read_counter(conn, &counter, sqlstate))
        return false;

    /*
     * Simulate another client by updating the row from a second
     * connection, after this transaction has read the row but before it
     * writes. This happens on the first attempt only.
     */
    if (attempt == 1 &&
        !update_from_other_connection(sqlstate, message, size))
        return false;

    /*
     * Under REPEATABLE READ, updating a row that another transaction
     * changed and committed since this transaction's snapshot was taken
     * fails with SQLSTATE 40001.
     */
    snprintf(next, sizeof(next), "%d", counter + 1);
    params[0] = next;
    params[1] = "1";
    return run_sql(conn,
                   "UPDATE cookbook_retry_transactions SET value = $1 "
                   "WHERE id = $2",
                   2, params, sqlstate, NULL, 0);
}
/* --8<-- [end:work] */

/* --8<-- [start:retry] */
/* The type of a function that does the work of one transaction. */
typedef bool (*work_fn)(PGconn *conn, int attempt, char *sqlstate,
                        char *message, size_t size);

/* Sleep for the given number of milliseconds. */
static void
pause_ms(long ms)
{
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};

    nanosleep(&ts, NULL);
}

/*
 * Run work() in a REPEATABLE READ transaction, and run it again if the
 * server reports a serialisation failure or a deadlock. Return true if a
 * transaction committed. On failure, print the saved error message to
 * stderr, because the caller cannot recover it from the connection.
 */
static bool
run_with_retry(PGconn *conn, work_fn work)
{
    char sqlstate[6];
    char message[512];

    for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)
    {
        bool ok;

        message[0] = '\0';
        ok = run_sql(conn, "BEGIN ISOLATION LEVEL REPEATABLE READ",
                     0, NULL, sqlstate, NULL, 0) &&
            work(conn, attempt, sqlstate, message, sizeof(message)) &&
            run_sql(conn, "COMMIT", 0, NULL, sqlstate, NULL, 0);

        if (ok)
        {
            printf("Attempt %d: committed\n", attempt);
            return true;
        }

        /*
         * End the failed transaction so that the session can start
         * another. The error message is kept, because the ROLLBACK
         * would otherwise replace it; the work may already have supplied
         * a message from another connection.
         */
        char ignored[6];

        if (message[0] == '\0')
            snprintf(message, sizeof(message), "%s", PQerrorMessage(conn));
        run_sql(conn, "ROLLBACK", 0, NULL, ignored, NULL, 0);

        /*
         * Any other error, or running out of attempts, is a real failure
         * that the caller must report.
         */
        if (!is_retryable(sqlstate) || attempt == MAX_ATTEMPTS)
        {
            fprintf(stderr, "Database error: %s", message);
            return false;
        }

        printf("Attempt %d: serialisation failure, retrying\n", attempt);
        /* A short, growing pause gives the competing transaction time. */
        pause_ms(50L * attempt);
    }
    return false;
}
/* --8<-- [end:retry] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    int counter;
    char sqlstate[6];
    PGconn *conn = connect_to_server();

    if (PQstatus(conn) != CONNECTION_OK)
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        if (!create_table(conn))
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        else if (run_with_retry(conn, increment_counter))
        {
            if (read_counter(conn, &counter, sqlstate))
            {
                printf("Counter value: %d\n", counter);
                status = EXIT_SUCCESS;
            }
            else
                fprintf(stderr, "Database error: %s",
                        PQerrorMessage(conn));
        }

        /* Drop the shared table even if the work failed. */
        drop_table(conn);
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
