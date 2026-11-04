/*
 * Ellie's Postgres Cookbook
 * Listening for notifications with LISTEN and NOTIFY, using libpq.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

/* --8<-- [start:imports] */
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libpq-fe.h>
/* --8<-- [end:imports] */

/* --8<-- [start:config] */
#define CHANNEL "cookbook_listen_notify"
#define TIMEOUT_MS 5000

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
 * libpq runs each command in autocommit mode unless the program sends
 * BEGIN, so LISTEN takes effect, and NOTIFY is delivered, as soon as the
 * command completes.
 */
static PGconn *
connect_to_server(void)
{
    const char *values[sizeof(keywords) / sizeof(keywords[0])];

    read_settings(values);
    return PQconnectdbParams(keywords, values, 0);
}
/* --8<-- [end:connect] */

/* --8<-- [start:listen] */
/*
 * Subscribe the connection to a channel, and return true on success. On
 * failure, PQerrorMessage() describes the error.
 */
static bool
listen_on(PGconn *conn, const char *channel)
{
    /*
     * LISTEN takes an identifier rather than a value, so it cannot use a
     * parameter; PQescapeIdentifier() quotes the name safely.
     */
    char *identifier = PQescapeIdentifier(conn, channel, strlen(channel));
    char *sql;
    PGresult *res;
    bool ok;

    if (identifier == NULL)
        return false;

    sql = malloc(strlen(identifier) + sizeof("LISTEN "));
    if (sql == NULL)
    {
        PQfreemem(identifier);
        return false;
    }
    sprintf(sql, "LISTEN %s", identifier);
    PQfreemem(identifier);

    res = PQexec(conn, sql);
    ok = PQresultStatus(res) == PGRES_COMMAND_OK;

    /* PQclear() frees the result, and accepts NULL. */
    PQclear(res);
    free(sql);
    return ok;
}
/* --8<-- [end:listen] */

/* --8<-- [start:notify] */
/*
 * Send a notification to every connection listening on a channel, and
 * return true on success.
 */
static bool
send_notification(PGconn *conn, const char *channel, const char *payload)
{
    /*
     * pg_notify() takes the channel and payload as ordinary parameters,
     * unlike the NOTIFY command, so libpq sends them separately.
     */
    const char *params[] = {channel, payload};
    PGresult *res = PQexecParams(conn, "SELECT pg_notify($1, $2)",
                                 2,     /* number of parameters */
                                 NULL,  /* let the server infer types */
                                 params,
                                 NULL,  /* text parameters need no lengths */
                                 NULL,  /* all parameters are text */
                                 0);    /* ask for text results */
    bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;

    PQclear(res);
    return ok;
}
/* --8<-- [end:notify] */

/* --8<-- [start:wait] */
/* Return the milliseconds from start to now, using a clock that never
 * goes backwards. */
static long
elapsed_ms(const struct timespec *start)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start->tv_sec) * 1000 +
           (now.tv_nsec - start->tv_nsec) / 1000000;
}

/*
 * Wait for a notification, and return it. The caller frees the
 * notification with PQfreemem(). On failure the function returns NULL and
 * sets *problem to NULL for a timeout, or to a message that describes an
 * error.
 *
 * libpq never reads from the socket by itself while the program is idle.
 * The loop therefore asks poll() to wait until the socket is readable,
 * calls PQconsumeInput() to read what arrived, and then asks PQnotifies()
 * for the next queued notification.
 */
static PGnotify *
wait_for_notification(PGconn *conn, int timeout_ms, const char **problem)
{
    struct timespec start;
    struct pollfd pfd;

    clock_gettime(CLOCK_MONOTONIC, &start);
    pfd.fd = PQsocket(conn);
    pfd.events = POLLIN;
    *problem = NULL;

    for (;;)
    {
        PGnotify *message;
        long remaining;
        int ready;

        if (!PQconsumeInput(conn))
        {
            *problem = PQerrorMessage(conn);
            return NULL;
        }

        message = PQnotifies(conn);
        if (message != NULL)
            return message;

        remaining = timeout_ms - elapsed_ms(&start);
        if (remaining <= 0)
            return NULL;

        ready = poll(&pfd, 1, (int) remaining);
        if (ready == 0)
            return NULL;

        /*
         * A signal can interrupt poll() with EINTR; the loop then works
         * out the remaining time again and retries. Any other failure is
         * an error, not a timeout.
         */
        if (ready < 0 && errno != EINTR)
        {
            *problem = strerror(errno);
            return NULL;
        }
    }
}
/* --8<-- [end:wait] */

/* --8<-- [start:main] */
int
main(void)
{
    int status = EXIT_FAILURE;
    PGconn *listener = connect_to_server();
    PGconn *sender = connect_to_server();
    PGnotify *message;
    const char *problem;

    if (PQstatus(listener) != CONNECTION_OK)
        fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
    else if (PQstatus(sender) != CONNECTION_OK)
        fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
    else if (!listen_on(listener, CHANNEL))
        fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
    else
    {
        printf("Listening on channel '%s'\n", CHANNEL);
        fflush(stdout);

        if (!send_notification(sender, CHANNEL, "Hello from connection B"))
            fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
        else if ((message = wait_for_notification(listener, TIMEOUT_MS,
                                                  &problem)) == NULL)
        {
            if (problem == NULL)
                fprintf(stderr, "No notification within %d seconds\n",
                        TIMEOUT_MS / 1000);
            else
                fprintf(stderr, "Wait failed: %s\n", problem);
        }
        else
        {
            printf("Received notification on '%s': %s\n",
                   message->relname, message->extra);
            PQfreemem(message);
            status = EXIT_SUCCESS;
        }
    }

    /* Close both connections whether or not an error occurred. */
    PQfinish(listener);
    PQfinish(sender);
    return status;
}
/* --8<-- [end:main] */
