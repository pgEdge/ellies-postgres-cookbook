/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL and running a scalar query, using libpq.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

/* --8<-- [start:imports] */
#include <stdio.h>
#include <stdlib.h>

#include <libpq-fe.h>
/* --8<-- [end:imports] */

/* --8<-- [start:errors] */
/*
 * Report a failure, release any resources we hold, and exit. PQclear()
 * and PQfinish() both accept NULL, so this is safe to call at any point.
 */
static void
fail(const char *what, PGconn *conn, PGresult *res)
{
    fprintf(stderr, "%s: %s", what, PQerrorMessage(conn));
    PQclear(res);
    PQfinish(conn);
    exit(EXIT_FAILURE);
}
/* --8<-- [end:errors] */

/* --8<-- [start:config] */
/* Return the value of an environment variable, or a fallback if unset. */
static const char *
env_or(const char *name, const char *fallback)
{
    const char *value = getenv(name);

    return (value != NULL && value[0] != '\0') ? value : fallback;
}

int
main(void)
{
    /*
     * Connection parameters are passed as two parallel, NULL-terminated
     * arrays of keywords and values. A NULL value is ignored, so the
     * password is only sent if PGPASSWORD is set.
     */
    const char *keywords[] = {
        "host", "port", "dbname", "user", "password", NULL
    };
    const char *values[] = {
        env_or("PGHOST", "localhost"),
        env_or("PGPORT", "5432"),
        env_or("PGDATABASE", "postgres"),
        env_or("PGUSER", "postgres"),
        env_or("PGPASSWORD", NULL),
        NULL
    };
    /* --8<-- [end:config] */

    /* --8<-- [start:connect] */
    PGconn *conn = PQconnectdbParams(keywords, values, 0);

    if (PQstatus(conn) != CONNECTION_OK)
        fail("Connection failed", conn, NULL);
    /* --8<-- [end:connect] */

    /* --8<-- [start:query] */
    /*
     * Always pass values as parameters rather than building them into
     * the SQL string; libpq sends them separately, so no quoting or
     * escaping is needed and SQL injection is impossible.
     */
    const char *params[] = {"int4"};
    PGresult *res = PQexecParams(conn,
                                 "SELECT count(*) FROM pg_catalog.pg_type "
                                 "WHERE typname = $1",
                                 1,     /* number of parameters */
                                 NULL,  /* let the server infer types */
                                 params,
                                 NULL,  /* text parameters need no lengths */
                                 NULL,  /* all parameters are text */
                                 0);    /* ask for text results */

    if (PQresultStatus(res) != PGRES_TUPLES_OK)
        fail("Query failed", conn, res);

    /* Results arrive as text, so convert the value to a number. */
    long long count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);

    printf("Number of types named 'int4': %lld\n", count);
    /* --8<-- [end:query] */

    /* --8<-- [start:cleanup] */
    PQclear(res);
    PQfinish(conn);

    return EXIT_SUCCESS;
    /* --8<-- [end:cleanup] */
}
