/*
 * Ellie's Postgres Cookbook
 * Loading rows in bulk with COPY, using libpq.
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

/* --8<-- [start:create_table] */
/*
 * Create a temporary table, which only this session can see and which
 * PostgreSQL drops when the session ends. Return true on success.
 */
static bool
create_table(PGconn *conn)
{
    PGresult *res = PQexec(conn,
                           "CREATE TEMPORARY TABLE items "
                           "(id int PRIMARY KEY, name text NOT NULL)");
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;

    PQclear(res);
    return ok;
}
/* --8<-- [end:create_table] */

/* --8<-- [start:generate_rows] */
/*
 * Copy a value into out in the COPY text format, in which a backslash, a
 * tab, a newline, and a carriage return all have a special meaning. The
 * caller must provide at least twice the length of the value, plus one.
 */
static void
escape_text(const char *value, char *out)
{
    for (; *value != '\0'; value++)
    {
        switch (*value)
        {
            case '\\': *out++ = '\\'; *out++ = '\\'; break;
            case '\t': *out++ = '\\'; *out++ = 't'; break;
            case '\n': *out++ = '\\'; *out++ = 'n'; break;
            case '\r': *out++ = '\\'; *out++ = 'r'; break;
            default:   *out++ = *value; break;
        }
    }
    *out = '\0';
}

/*
 * Format the row with the given id as one line of COPY text: the columns
 * are separated by a tab, and the row ends with a newline. Return the
 * length of the line.
 */
static int
format_row(int id, char *line, size_t size)
{
    char name[32];
    char escaped[64];

    snprintf(name, sizeof(name), "item %d", id);
    escape_text(name, escaped);
    return snprintf(line, size, "%d\t%s\n", id, escaped);
}
/* --8<-- [end:generate_rows] */

/* --8<-- [start:copy_rows] */
/*
 * Load rows with ids 1 to count using COPY ... FROM STDIN, and store the
 * number of rows the server stored in *copied. Return true on success.
 */
static bool
copy_rows(PGconn *conn, int count, long long *copied)
{
    PGresult *res = PQexec(conn, "COPY items (id, name) FROM STDIN");
    bool ok = PQresultStatus(res) == PGRES_COPY_IN;

    PQclear(res);
    if (!ok)
        return false;

    /*
     * Send the rows one at a time. libpq buffers the data and sends it
     * in large chunks, so this is much faster than one INSERT for each
     * row, and the program never holds more than one row.
     */
    for (int id = 1; id <= count; id++)
    {
        char line[128];
        int length = format_row(id, line, sizeof(line));

        if (PQputCopyData(conn, line, length) != 1)
            return false;
    }

    /*
     * A NULL error message ends the copy normally; a message would abort
     * it instead. The server's verdict arrives as the next result.
     */
    if (PQputCopyEnd(conn, NULL) != 1)
        return false;

    res = PQgetResult(conn);
    ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    if (ok)
        *copied = strtoll(PQcmdTuples(res), NULL, 10);
    PQclear(res);

    /* Read until PQgetResult() returns NULL, leaving the connection idle. */
    while ((res = PQgetResult(conn)) != NULL)
        PQclear(res);
    return ok;
}
/* --8<-- [end:copy_rows] */

/* --8<-- [start:summarise] */
/*
 * Store the number of rows in the table and the sum of their ids in
 * *count and *total, and return true on success.
 */
static bool
summarise(PGconn *conn, long long *count, long long *total)
{
    PGresult *res = PQexec(conn, "SELECT count(*), sum(id) FROM items");
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    /* Results arrive as text, so convert the values to numbers. */
    if (ok)
    {
        *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);
        *total = strtoll(PQgetvalue(res, 0, 1), NULL, 10);
    }

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    return ok;
}
/* --8<-- [end:summarise] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    long long copied;
    long long count;
    long long total;
    PGconn *conn = connect_to_server();

    /* The || operator skips each step once a step has failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !create_table(conn) ||
        !copy_rows(conn, 1000, &copied) ||
        !summarise(conn, &count, &total))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        printf("Copied %lld rows\n", copied);
        printf("Rows in table: %lld\n", count);
        printf("Sum of ids: %lld\n", total);
        status = EXIT_SUCCESS;
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
