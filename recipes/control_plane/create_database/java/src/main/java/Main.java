/*
 * Ellie's Postgres Cookbook
 * Creating a pgEdge Control Plane database on one host, waiting until it
 * is available, and deleting it again, using java.net.http and Jackson.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The database runs in containers on the host until it is deleted, so
 * this program deletes the database it creates on every path: after a
 * success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    // The new database listens on the given port on its host, so choose
    // one that is free.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String PORT = envOr("CONTROL_PLANE_RECIPE_PORT", "6433");

    static final Duration TIMEOUT = Duration.ofSeconds(30);

    // How long to wait for a database to become available, or to
    // disappear after a delete, and how often to check.
    static final Duration WAIT_FOR = Duration.ofSeconds(600);
    static final Duration POLL_INTERVAL = Duration.ofSeconds(5);

    /**
     * Thrown when the Control Plane rejects a request or replies oddly.
     * The status is the HTTP status of the reply, or 0 if there was none.
     */
    static class ControlPlaneException extends Exception {
        final int status;

        ControlPlaneException(String message, int status) {
            super(message);
            this.status = status;
        }

        ControlPlaneException(String message) {
            this(message, 0);
        }
    }

    // A client and a mapper are safe to share, so the program creates only
    // one of each.
    static final HttpClient CLIENT = HttpClient.newHttpClient();
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            pending.cancel(true);
            throw new HttpTimeoutException("request timed out");
        } catch (ExecutionException e) {
            if (e.getCause() instanceof IOException cause) {
                throw cause;
            }
            throw new IOException(e.getCause());
        }
    }

    /**
     * Sends a request to the server, with the body encoded as JSON if it
     * is not null, and returns the decoded reply.
     */
    static JsonNode call(String method, String path, Object body)
            throws IOException, InterruptedException, ControlPlaneException {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT);
        if (body == null) {
            builder.method(method, HttpRequest.BodyPublishers.noBody());
        } else {
            builder.header("Content-Type", "application/json")
                    .method(method, HttpRequest.BodyPublishers.ofString(
                            MAPPER.writeValueAsString(body)));
        }
        HttpResponse<String> response = send(builder.build());
        if (response.statusCode() >= 400) {
            throw new ControlPlaneException("HTTP " + response.statusCode()
                    + ", " + shorten(response.body()), response.statusCode());
        }
        try {
            JsonNode reply = MAPPER.readTree(response.body());
            if (reply.isObject()) {
                return reply;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:config]

    // --8<-- [start:host]
    /**
     * Returns the ID of the first host in the cluster. A database places
     * each of its nodes on one or more hosts, which run the Postgres
     * containers.
     */
    static String firstHost()
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode hosts = call("GET", "/v1/hosts", null).path("hosts");
        if (hosts.isEmpty()) {
            throw new ControlPlaneException("the cluster has no hosts");
        }
        return hosts.get(0).path("id").asString();
    }
    // --8<-- [end:host]

    // --8<-- [start:create]
    /**
     * Asks the Control Plane to create a database with one node. The reply
     * holds the database and the task that creates it; the work happens in
     * the background after the reply.
     */
    static void createDatabase(String databaseId, String host)
            throws IOException, InterruptedException, ControlPlaneException {
        Map<String, Object> body = Map.of(
                "id", databaseId,
                "spec", Map.of(
                        "database_name", "recipe",
                        "port", Integer.parseInt(PORT),
                        "nodes", List.of(Map.of(
                                "name", "n1",
                                "host_ids", List.of(host)))));
        call("POST", "/v1/databases", body);
    }
    // --8<-- [end:create]

    // --8<-- [start:wait]
    /**
     * Polls the database, printing its state each time it changes, until
     * the state is available, and returns the port of its first instance.
     * Each instance runs one node, and its connection_info holds the
     * address and port that clients use. A failed state ends the wait at
     * once.
     */
    static int waitUntilAvailable(String databaseId)
            throws IOException, InterruptedException, ControlPlaneException {
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String last = "";
        while (System.nanoTime() < deadline) {
            JsonNode database = call("GET", "/v1/databases/" + databaseId, null);
            String state = database.path("state").asString("");
            if (!state.equals(last)) {
                System.out.println("Database state: " + state);
                last = state;
            }
            if (state.equals("available")) {
                JsonNode instance = database.path("instances").path(0);
                if (instance.isMissingNode()) {
                    throw new ControlPlaneException(
                            "the database is available but has no instances");
                }
                return instance.path("connection_info").path("port").asInt();
            }
            if (state.equals("failed")) {
                throw new ControlPlaneException("the database has the state failed");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the database was not available after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    // --8<-- [end:wait]

    // --8<-- [start:delete]
    /**
     * Reports whether a failed request is worth repeating: no reply
     * arrived, the server failed, or it answered 409, which the Control
     * Plane does whilst another task, such as the create, is still running
     * on the database.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ControlPlaneException cpe) {
            return cpe.status == 409 || cpe.status >= 500;
        }
        return e instanceof IOException;
    }

    static boolean isGone(Exception e) {
        return e instanceof ControlPlaneException cpe && cpe.status == 404;
    }

    /**
     * Deletes the database and waits until the API no longer has it. A 404
     * means that the database is already gone.
     */
    static void deleteDatabase(String databaseId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + databaseId;
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String taskId;
        while (true) {
            try {
                taskId = call("DELETE", path, null).path("task").path("task_id").asString("");
                break;
            } catch (IOException | ControlPlaneException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e) || System.nanoTime() >= deadline) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }

        if (taskId.isEmpty()) {
            throw new ControlPlaneException("the delete reply has no task");
        }

        // The delete starts a task that removes the database; a 404 shows
        // that it has finished. Whilst the database is still there, the
        // status of the task shows whether the delete failed.
        while (System.nanoTime() < deadline) {
            try {
                call("GET", path, null);
                String status = call("GET", path + "/tasks/" + taskId, null)
                        .path("status").asString("");
                if (status.equals("failed") || status.equals("canceled")) {
                    throw new ControlPlaneException(
                            "the delete task finished with the status " + status);
                }
            } catch (IOException | ControlPlaneException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e)) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the database was still present after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    // --8<-- [end:delete]

    // --8<-- [start:main]
    // Ctrl-C and SIGTERM start the JVM's shutdown, which runs the hook
    // below and then ends the process. The hook interrupts the main thread
    // and waits until it has deleted the database. The lock and the
    // cleaning flag stop the hook from interrupting the cleanup itself.
    static final Object LOCK = new Object();
    static final CountDownLatch FINISHED = new CountDownLatch(1);
    static boolean cleaning = false;
    static volatile boolean shuttingDown = false;

    public static void main(String[] args) {
        // The new database listens on this port, so check it before
        // creating anything.
        if (!PORT.matches("[1-9][0-9]{0,4}") || Integer.parseInt(PORT) > 65535) {
            System.err.println("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
            System.exit(1);
        }

        Thread mainThread = Thread.currentThread();
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            shuttingDown = true;
            synchronized (LOCK) {
                if (!cleaning) {
                    mainThread.interrupt();
                }
            }
            try {
                FINISHED.await();
            } catch (InterruptedException e) {
                // The JVM is ending anyway.
            }
        }));

        int exitCode = 0;
        boolean created = false;
        // The client chooses the ID of a new database, so the program knows
        // it before the request, and can delete the database even if the
        // reply never arrives. The random suffix keeps the ID unique.
        byte[] suffix = new byte[3];
        new SecureRandom().nextBytes(suffix);
        String databaseId = "cookbook-recipe-" + HexFormat.of().formatHex(suffix);
        try {
            String host = firstHost();
            System.out.println("Host: " + host);

            // Clean up unless the server refused the request with a 4xx
            // status, which means it created nothing; a 409, for example,
            // means that a database with this ID already exists, and is not
            // this program's to delete.
            created = true;
            try {
                createDatabase(databaseId, host);
            } catch (ControlPlaneException e) {
                if (e.status >= 400 && e.status < 500) {
                    created = false;
                }
                throw e;
            }
            System.out.println("Created database " + databaseId);

            int port = waitUntilAvailable(databaseId);
            System.out.println("Database is available on port " + port);
        } catch (InterruptedException e) {
            System.err.println("Interrupted");
            exitCode = 130;
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException e) {
            System.err.println("Control Plane error: " + e);
            exitCode = 1;
        } catch (ControlPlaneException | RuntimeException e) {
            System.err.println("Control Plane error: " + e.getMessage());
            exitCode = 1;
        } finally {
            // From here on, a signal does not interrupt the main thread, and
            // any interrupt that arrived before this point is cleared, so
            // that the cleanup can wait between its requests.
            synchronized (LOCK) {
                cleaning = true;
                // A signal that arrived after the last request still counts.
                if (Thread.interrupted() && exitCode == 0) {
                    System.err.println("Interrupted");
                    exitCode = 130;
                }
            }
            // Delete the database whether the example succeeded, failed, or
            // was interrupted.
            if (created) {
                try {
                    deleteDatabase(databaseId);
                    System.out.println("Deleted database");
                } catch (IOException | InterruptedException | ControlPlaneException e) {
                    System.err.println("Control Plane error: " + e);
                    System.err.println("Delete the database " + databaseId + " by hand");
                    exitCode = 1;
                }
            }
        }

        System.out.flush();
        FINISHED.countDown();
        // Once the JVM has started to shut down, System.exit() would wait
        // for the hook forever, so after a signal the program halts with
        // its exit code instead.
        if (shuttingDown) {
            Runtime.getRuntime().halt(exitCode);
        }
        System.exit(exitCode);
    }
    // --8<-- [end:main]
}
