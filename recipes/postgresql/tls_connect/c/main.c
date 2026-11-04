/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL over TLS with full verification, using libpq.
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
    "host", "port", "dbname", "user", "password",
    "sslmode", "sslrootcert", NULL
};

/*
 * Fill in the value for each keyword from the environment, and return
 * false if PGSSLROOTCERT is missing. It has no default, because
 * verification is meaningless without the certificate of the authority
 * that signed the server certificate.
 */
static bool
read_settings(const char *values[])
{
    values[0] = env_or("PGHOST", "localhost");
    values[1] = env_or("PGPORT", "5432");
    values[2] = env_or("PGDATABASE", "postgres");
    values[3] = env_or("PGUSER", "postgres");
    values[4] = env_or("PGPASSWORD", NULL);

    /*
     * verify-full checks that the certificate chains to the root
     * certificate and that it matches the host name. Weaker modes, such
     * as require, encrypt the connection without proving who is on the
     * other end.
     */
    values[5] = "verify-full";
    values[6] = env_or("PGSSLROOTCERT", NULL);
    values[7] = NULL;
    return values[6] != NULL;
}
/* --8<-- [end:config] */

/* --8<-- [start:connect] */
/*
 * Open a verified TLS connection with the settings from the environment,
 * or return NULL if PGSSLROOTCERT is missing. libpq otherwise always
 * returns a connection object, which the caller must check with
 * PQstatus() and release with PQfinish(), even if the connection attempt
 * failed; the attempt fails if verification fails.
 */
static PGconn *
connect_to_server(void)
{
    const char *values[sizeof(keywords) / sizeof(keywords[0])];

    if (!read_settings(values))
        return NULL;
    return PQconnectdbParams(keywords, values, 0);
}
/* --8<-- [end:connect] */

/* --8<-- [start:query] */
/*
 * Store in *encrypted whether the server reports this connection as using
 * TLS, and return true on success. On failure, PQerrorMessage() describes
 * the error.
 */
static bool
connection_is_encrypted(PGconn *conn, bool *encrypted)
{
    /*
     * pg_stat_ssl has one row for each connection; pg_backend_pid()
     * identifies the one that belongs to this session. The version column
     * holds the protocol version, such as TLSv1.3.
     */
    PGresult *res = PQexec(conn,
                           "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                           "WHERE pid = pg_backend_pid()");
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK && PQntuples(res) == 1;

    /* Results arrive as text; PostgreSQL writes a boolean as t or f. */
    if (ok)
        *encrypted = strcmp(PQgetvalue(res, 0, 0), "t") == 0;

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
    bool encrypted;
    PGconn *conn = connect_to_server();

    if (conn == NULL)
    {
        fprintf(stderr, "Database error: PGSSLROOTCERT must name the "
                        "root certificate\n");
        return status;
    }

    /* The || operator skips the query if the connection failed. */
    if (PQstatus(conn) != CONNECTION_OK ||
        !connection_is_encrypted(conn, &encrypted))
    {
        fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
    }
    else
    {
        printf("Connection is encrypted: %s\n", encrypted ? "true" : "false");
        /*
         * Reaching this line means that verify-full succeeded; a
         * certificate or host name mismatch fails the connection instead.
         */
        printf("Server certificate verified: true\n");
        status = EXIT_SUCCESS;
    }

    /* Close the connection whether or not an error occurred. */
    PQfinish(conn);
    return status;
}
/* --8<-- [end:main] */
