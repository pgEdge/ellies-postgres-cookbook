/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL and running a scalar query, using libpq.
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

/* --8<-- [start:query] */
/*
 * Store the number of data types with the given name in *count, and
 * return true on success. On failure, PQerrorMessage() describes the
 * error.
 */
static bool
count_types(PGconn *conn, const char *name, long long *count)
{
    /*
     * Always pass values as parameters rather than building them into
     * the SQL string; libpq sends them separately, so no quoting or
     * escaping is needed and SQL injection is impossible.
     */
    const char *params[] = {name};
    PGresult *res = PQexecParams(conn,
                                 "SELECT count(*) FROM pg_catalog.pg_type "
                                 "WHERE typname = $1",
                                 1,     /* number of parameters */
                                 NULL,  /* let the server infer types */
                                 params,
                                 NULL,  /* text parameters need no lengths */
                                 NULL,  /* all parameters are text */
                                 0);    /* ask for text results */
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    /* Results arrive as text, so convert the value to a number. */
    if (ok)
        *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    return ok;
}
/* --8<-- [end:query] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    long long count;
    PGconn *conn = connect_to_server();

    /* The || operator skips the query if the connection failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !count_types(conn, "int4", &count))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        printf("Number of types named 'int4': %lld\n", count);
        status = EXIT_SUCCESS;
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
