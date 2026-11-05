/*
 * Ellie's Postgres Cookbook
 * Changing a Postgres setting of a pgEdge Control Plane database, checking
 * it from a connection, and putting the original settings back, using
 * java.net.http, Jackson and pgJDBC.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The program restores the original settings on every path: after a
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
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ObjectNode;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    // The password has no default; the Control Plane never returns it, so
    // it comes from whoever created the database user.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
    static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);

    static final Duration TIMEOUT = Duration.ofSeconds(30);

    // The setting to change, and its new value.
    static final String SETTING = "work_mem";
    static final String VALUE = "16MB";

    // How long to wait for an update to finish, and how often to check.
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

    // --8<-- [start:update]
    /**
     * Sends a whole database spec as an update, and returns the ID of the
     * task that applies it. The Control Plane compares the spec with the
     * current one and changes only what differs; the work happens in the
     * task after the reply. The spec is kept as a JSON tree, so that the
     * update sends back every field that the server returned.
     */
    static String updateDatabase(JsonNode spec)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode reply = call("POST", "/v1/databases/" + DATABASE_ID, Map.of("spec", spec));
        String taskId = reply.path("task").path("task_id").asString("");
        if (taskId.isEmpty()) {
            throw new ControlPlaneException("Unexpected response: missing task_id");
        }
        return taskId;
    }

    /**
     * Returns a copy of the spec with the setting changed. postgresql_conf
     * holds the Postgres settings that the Control Plane manages, and may
     * be missing.
     */
    static JsonNode changedSpec(JsonNode spec) {
        ObjectNode changed = (ObjectNode) spec.deepCopy();
        if (!changed.path("postgresql_conf").isObject()) {
            changed.putObject("postgresql_conf");
        }
        ((ObjectNode) changed.get("postgresql_conf")).put(SETTING, VALUE);
        return changed;
    }
    // --8<-- [end:update]

    // --8<-- [start:wait]
    /**
     * Reports whether a failed request is worth repeating: no reply
     * arrived, the server failed, or it answered 409, which the Control
     * Plane does whilst another task, such as the update, is still running
     * on the database.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ControlPlaneException cpe) {
            return cpe.status == 409 || cpe.status >= 500;
        }
        return e instanceof IOException;
    }

    /**
     * Polls a task until it finishes, and throws unless it completed. A
     * failed poll is repeated if it is worth repeating.
     */
    static void waitForTask(String taskId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        while (System.nanoTime() < deadline) {
            String status = "";
            try {
                status = call("GET", path, null).path("status").asString("");
            } catch (IOException | ControlPlaneException e) {
                if (!isTransient(e)) {
                    throw e;
                }
            }
            if (status.equals("completed")) {
                return;
            }
            if (status.equals("failed") || status.equals("canceled")) {
                throw new ControlPlaneException(
                        "the task finished with the status " + status);
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the task was still running after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    // --8<-- [end:wait]

    // --8<-- [start:connect]
    /**
     * Connects to the first available instance and returns the current
     * value of the setting. Each instance runs one node, and its
     * connection_info holds the address and port that clients use.
     */
    static String showSetting()
            throws IOException, InterruptedException, ControlPlaneException, SQLException {
        JsonNode database = call("GET", "/v1/databases/" + DATABASE_ID, null);
        JsonNode info = null;
        for (JsonNode instance : database.path("instances")) {
            JsonNode candidate = instance.path("connection_info");
            if (instance.path("state").asString("").equals("available")
                    && !candidate.path("addresses").isEmpty()) {
                info = candidate;
                break;
            }
        }
        if (info == null) {
            throw new ControlPlaneException("no available instance of " + DATABASE_ID);
        }

        Properties props = new Properties();
        props.setProperty("user", DATABASE_USER);
        props.setProperty("password", DATABASE_PASSWORD);
        props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
        String url = "jdbc:postgresql://" + info.path("addresses").get(0).asString()
                + ":" + info.path("port").asInt() + "/"
                + database.path("spec").path("database_name").asString();

        // try-with-resources closes the connection and statement when the
        // block exits, whether or not the query failed.
        try (Connection conn = DriverManager.getConnection(url, props);
             PreparedStatement stmt = conn.prepareStatement("SELECT current_setting(?)")) {
            stmt.setString(1, SETTING);
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getString(1);
            }
        }
    }
    // --8<-- [end:connect]

    // --8<-- [start:restore]
    /**
     * Sends the original spec back and waits for the task. The Control
     * Plane answers 409 whilst another task, such as the update, is still
     * running on the database, so the program repeats the request, as it
     * does when no reply arrived or the server failed.
     */
    static void restore(JsonNode original)
            throws IOException, InterruptedException, ControlPlaneException {
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String taskId;
        while (true) {
            try {
                taskId = updateDatabase(original);
                break;
            } catch (IOException | ControlPlaneException e) {
                if (!isTransient(e) || System.nanoTime() >= deadline) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        waitForTask(taskId);
    }
    // --8<-- [end:restore]

    // --8<-- [start:main]
    // Ctrl-C and SIGTERM start the JVM's shutdown, which runs the hook
    // below and then ends the process. The hook interrupts the main thread
    // and waits until it has restored the settings. The lock and the
    // cleaning flag stop the hook from interrupting the cleanup itself.
    static final Object LOCK = new Object();
    static final CountDownLatch FINISHED = new CountDownLatch(1);
    static boolean cleaning = false;
    static volatile boolean shuttingDown = false;

    public static void main(String[] args) {
        if (DATABASE_PASSWORD == null) {
            System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
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
        boolean changed = false;
        JsonNode original = null;
        try {
            // The spec that the API returns leaves out the passwords of the
            // database users, and an update may leave them out too, which
            // keeps them unchanged.
            original = call("GET", "/v1/databases/" + DATABASE_ID, null).path("spec");

            // Restore unless the server refused the request with a 4xx
            // status, which means that it changed nothing.
            System.out.println("Setting " + SETTING + " to " + VALUE);
            changed = true;
            String taskId;
            try {
                taskId = updateDatabase(changedSpec(original));
            } catch (ControlPlaneException e) {
                if (e.status >= 400 && e.status < 500) {
                    changed = false;
                }
                throw e;
            }
            waitForTask(taskId);
            System.out.println("Update completed");

            System.out.println(SETTING + " is now " + showSetting());
        } catch (InterruptedException e) {
            System.err.println("Interrupted");
            exitCode = 130;
        // SQLException covers the driver's errors, including a failure to
        // connect.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            exitCode = 1;
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
                // The database connection does not stop for a signal, so
                // check whether one arrived whilst it was open.
                if (Thread.interrupted() && exitCode == 0) {
                    System.err.println("Interrupted");
                    exitCode = 130;
                }
            }
            // Restore the original settings whether the example succeeded,
            // failed, or was interrupted.
            if (changed) {
                try {
                    restore(original);
                    System.out.println("Restored the original settings");
                } catch (IOException | InterruptedException | ControlPlaneException e) {
                    System.err.println("Control Plane error: " + e);
                    System.err.println("Restore the settings of the database "
                            + DATABASE_ID + " by hand");
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
