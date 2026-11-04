/*
 * Ellie's Postgres Cookbook
 * Storing and searching vectors with pgvector, using libpq.
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

/* --8<-- [start:schema] */
/*
 * Enable pgvector and create a temporary table of colours, returning true
 * on success. vector(3) fixes the number of dimensions, one for each of
 * the red, green, and blue components. The temporary table disappears
 * when the session ends, so the program can run repeatedly. An HNSW index
 * speeds up nearest-neighbour searches; vector_l2_ops matches the <->
 * (Euclidean distance) operator used by the search.
 */
static bool
create_schema(PGconn *conn)
{
    static const char *const statements[] = {
        "CREATE EXTENSION IF NOT EXISTS vector",
        "CREATE TEMPORARY TABLE colours ("
        "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
        "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
    };

    for (size_t i = 0; i < sizeof(statements) / sizeof(statements[0]); i++)
    {
        PGresult *res = PQexec(conn, statements[i]);
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

        PQclear(res);
        if (!ok)
            return false;
    }
    return true;
}
/* --8<-- [end:schema] */

/* --8<-- [start:insert] */
/* Store five colours, each as a vector of its RGB components. */
static bool
insert_colours(PGconn *conn)
{
    static const char *const colours[][2] = {
        {"red", "[1,0,0]"},
        {"green", "[0,1,0]"},
        {"blue", "[0,0,1]"},
        {"yellow", "[1,1,0]"},
        {"white", "[1,1,1]"},
    };

    for (size_t i = 0; i < sizeof(colours) / sizeof(colours[0]); i++)
    {
        /*
         * A vector travels as text in pgvector's [x,y,z] format, and the
         * ::vector cast converts it on the server, so libpq needs no
         * vector-specific support.
         */
        PGresult *res = PQexecParams(conn,
                                     "INSERT INTO colours (name, rgb) "
                                     "VALUES ($1, $2::vector)",
                                     2,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     colours[i],
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

        PQclear(res);
        if (!ok)
            return false;
    }
    return true;
}
/* --8<-- [end:insert] */

/* --8<-- [start:search] */
/*
 * Print the names of the colours nearest to the target vector, and return
 * true on success. On failure, PQerrorMessage() describes the error.
 */
static bool
print_nearest_colours(PGconn *conn, const char *target, int count)
{
    char limit[16];
    const char *params[] = {target, limit};
    PGresult *res;
    bool ok;

    /* Every parameter is sent as text, including the limit. */
    snprintf(limit, sizeof(limit), "%d", count);

    /*
     * <-> is the Euclidean (L2) distance operator, so ordering by it puts
     * the nearest colour first.
     */
    res = PQexecParams(conn,
                       "SELECT name FROM colours "
                       "ORDER BY rgb <-> $1::vector LIMIT $2",
                       2,     /* number of parameters */
                       NULL,  /* let the server infer types */
                       params,
                       NULL,  /* text parameters need no lengths */
                       NULL,  /* all parameters are text */
                       0);    /* ask for text results */
    ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    if (ok)
    {
        printf("Colours nearest to %s:\n", target);
        for (int row = 0; row < PQntuples(res); row++)
            printf("%d. %s\n", row + 1, PQgetvalue(res, row, 0));
    }

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    return ok;
}
/* --8<-- [end:search] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    PGconn *conn = connect_to_server();

    /* The || operator skips each step if an earlier one failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !create_schema(conn) ||
        !insert_colours(conn) ||
        !print_nearest_colours(conn, "[0.9,0.7,0.2]", 3))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        status = EXIT_SUCCESS;
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
