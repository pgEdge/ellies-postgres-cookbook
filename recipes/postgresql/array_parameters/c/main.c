/*
 * Ellie's Postgres Cookbook
 * Passing a list of values as a single array parameter, using libpq.
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

/* --8<-- [start:query] */
/*
 * Build the text form of a PostgreSQL array from a list of strings, such
 * as {"int4","text"}. Every element is wrapped in double quotes, and any
 * backslash or double quote inside an element is escaped with a
 * backslash, so no element can end early or add elements. The caller
 * frees the result with free(); NULL means that memory ran out.
 */
static char *
array_literal(const char *const *names, int count)
{
    size_t size = 3;    /* braces and the terminating NUL */
    char *literal;
    char *out;

    /* Worst case, every character needs a backslash, plus two quotes and
     * a comma for each element. */
    for (int i = 0; i < count; i++)
        size += 2 * strlen(names[i]) + 3;

    literal = malloc(size);
    if (literal == NULL)
        return NULL;

    out = literal;
    *out++ = '{';
    for (int i = 0; i < count; i++)
    {
        if (i > 0)
            *out++ = ',';
        *out++ = '"';
        for (const char *p = names[i]; *p != '\0'; p++)
        {
            if (*p == '"' || *p == '\\')
                *out++ = '\\';
            *out++ = *p;
        }
        *out++ = '"';
    }
    *out++ = '}';
    *out = '\0';
    return literal;
}

/*
 * Print the names from the list that exist as data types, in the format
 * of the expected output, and return true on success. On failure,
 * PQerrorMessage() describes the error.
 */
static bool
find_types(PGconn *conn, const char *const *names, int count)
{
    /*
     * The whole list travels as one array parameter, so the SQL text is
     * the same however many values the list holds. libpq has no array
     * type of its own, so the parameter is the text form of an array, and
     * the cast tells the server how to read it.
     */
    char *literal = array_literal(names, count);
    const char *params[1];
    PGresult *res;
    bool ok;

    if (literal == NULL)
        return false;
    params[0] = literal;

    res = PQexecParams(conn,
                       "SELECT typname FROM pg_catalog.pg_type "
                       "WHERE typname = ANY($1::text[]) ORDER BY typname",
                       1,       /* number of parameters */
                       NULL,    /* let the server infer types */
                       params,
                       NULL,    /* text parameters need no lengths */
                       NULL,    /* all parameters are text */
                       0);      /* ask for text results */
    ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    if (ok)
    {
        int found = PQntuples(res);

        printf("Found %d of %d types: ", found, count);
        for (int i = 0; i < found; i++)
            printf("%s%s", i > 0 ? ", " : "", PQgetvalue(res, i, 0));
        printf("\n");
    }

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    free(literal);
    return ok;
}
/* --8<-- [end:query] */

/* --8<-- [start:main] */
int
main(void)
{
    const char *const wanted[] = {"int4", "text", "bool", "no_such_type"};
    int status = EXIT_FAILURE;
    PGconn *conn = connect_to_server();

    /* The || operator skips the query if the connection failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !find_types(conn, wanted, 4))
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    else
        status = EXIT_SUCCESS;

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
