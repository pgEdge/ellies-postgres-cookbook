/*
 * Ellie's Postgres Cookbook
 * Inserting rows and reading generated keys, using libpq.
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

/* --8<-- [start:setup] */
/*
 * Create a temporary table whose id column the server fills in, and
 * return true on success. GENERATED ALWAYS AS IDENTITY makes the server
 * assign each id from a sequence, and refuses any attempt to supply one.
 */
static bool
create_people(PGconn *conn)
{
    PGresult *res = PQexec(conn,
                           "CREATE TEMPORARY TABLE people ("
                           "id int GENERATED ALWAYS AS IDENTITY "
                           "PRIMARY KEY, "
                           "name text NOT NULL)");
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

    PQclear(res);
    return ok;
}
/* --8<-- [end:setup] */

/* --8<-- [start:add_person] */
/*
 * Insert a row and store the id that the server generated in *id, and
 * return true on success. On failure, PQerrorMessage() describes the
 * error.
 */
static bool
add_person(PGconn *conn, const char *name, int *id)
{
    /*
     * RETURNING makes the INSERT produce a result row, like a SELECT, so
     * the program learns the new id without a second query. The name is a
     * parameter, which libpq sends separately from the SQL text.
     */
    const char *params[] = {name};
    PGresult *res = PQexecParams(conn,
                                 "INSERT INTO people (name) VALUES ($1) "
                                 "RETURNING id",
                                 1,     /* number of parameters */
                                 NULL,  /* let the server infer types */
                                 params,
                                 NULL,  /* text parameters need no lengths */
                                 NULL,  /* all parameters are text */
                                 0);    /* ask for text results */
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    /* Results arrive as text, so convert the value to a number. */
    if (ok)
        *id = atoi(PQgetvalue(res, 0, 0));

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    return ok;
}
/* --8<-- [end:add_person] */

/* --8<-- [start:main] */
int
main(void)
{
    static const char *const names[] = {
        "Jane Doe", "John Smith", "Alex Example"
    };
    int status = EXIT_FAILURE;
    int id;
    size_t i;
    PGconn *conn = connect_to_server();

    if (PQstatus(conn) != CONNECTION_OK || !create_people(conn))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        PQfinish(conn);
        return status;
    }

    status = EXIT_SUCCESS;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
    {
        if (!add_person(conn, names[i], &id))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            status = EXIT_FAILURE;
            break;
        }
        printf("Inserted '%s' with id %d\n", names[i], id);
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
