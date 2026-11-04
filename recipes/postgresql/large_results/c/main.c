/*
 * Ellie's Postgres Cookbook
 * Reading a large result in batches, using libpq.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

/* --8<-- [start:imports] */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

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

/* --8<-- [start:read_batches] */
#define BATCH_SIZE 1000

/* Run a command that returns no rows, and return true on success. */
static bool
run_command(PGconn *conn, const char *sql)
{
    PGresult *res = PQexec(conn, sql);
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

    PQclear(res);
    return ok;
}

/*
 * Read every row of a large result, one batch at a time, and store the
 * number of rows and the sum of their values in *rows_read and *total.
 * Return true on success.
 */
static bool
read_in_batches(PGconn *conn, long long *rows_read, long long *total)
{
    char fetch[64];
    bool ok;

    *rows_read = 0;
    *total = 0;

    /* The batch size is a constant, so it is safe to put in the SQL. */
    snprintf(fetch, sizeof(fetch), "FETCH %d FROM large_results", BATCH_SIZE);

    /*
     * PQexec() would copy the whole result into memory. A cursor, which
     * lives only inside a transaction, makes the server hold the result
     * and hand out rows on request instead. The cursor name is a fixed
     * string, not application data, because a name cannot be a parameter.
     */
    ok = run_command(conn, "BEGIN") &&
         run_command(conn,
                     "DECLARE large_results CURSOR FOR "
                     "SELECT g FROM generate_series(1, 100000) AS g");

    while (ok)
    {
        /* FETCH returns the next batch, and no rows at the end. */
        PGresult *res = PQexec(conn, fetch);
        int rows;

        if (PQresultStatus(res) != PGRES_TUPLES_OK)
        {
            PQclear(res);
            ok = false;
            break;
        }

        rows = PQntuples(res);
        for (int row = 0; row < rows; row++)
        {
            /* Results arrive as text, so convert the value to a number. */
            *rows_read += 1;
            *total += strtoll(PQgetvalue(res, row, 0), NULL, 10);
        }
        PQclear(res);

        if (rows == 0)
            break;
    }

    /*
     * Ending the transaction also closes the cursor. COMMIT after an
     * error is harmless, because the server then rolls back.
     */
    return run_command(conn, "COMMIT") && ok;
}
/* --8<-- [end:read_batches] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    long long rows_read;
    long long total;
    PGconn *conn = connect_to_server();

    /* The || operator skips the read if the connection failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !read_in_batches(conn, &rows_read, &total))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        printf("Rows read: %lld\n", rows_read);
        printf("Sum of values: %lld\n", total);
        status = EXIT_SUCCESS;
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
