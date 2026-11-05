/*
 * Ellie's Postgres Cookbook
 * Finding the task that created a pgEdge Control Plane database, and
 * following its log until the task finishes, using java.net.http and
 * Jackson.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
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

    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");

    static final Duration TIMEOUT = Duration.ofSeconds(30);

    // How long to follow a task that is still running, and how often to
    // check.
    static final Duration FOLLOW_FOR = Duration.ofSeconds(600);
    static final Duration POLL_INTERVAL = Duration.ofSeconds(5);

    // The statuses after which a task does not change again.
    static final Set<String> FINAL_STATUSES = Set.of("completed", "failed", "canceled");

    /** Thrown when the Control Plane rejects a request or replies oddly. */
    static class ControlPlaneException extends Exception {
        ControlPlaneException(String message) {
            super(message);
        }
    }

    // A mapper is safe to share, so the program creates only one.
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
    static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws IOException, InterruptedException {
        CompletableFuture<HttpResponse<String>> pending =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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

    /** Fetches a path from the server, and returns the decoded reply. */
    static JsonNode get(HttpClient client, String path)
            throws IOException, InterruptedException, ControlPlaneException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(client, request);
        if (response.statusCode() >= 400) {
            throw new ControlPlaneException("HTTP " + response.statusCode()
                    + ", " + shorten(response.body()));
        }
        try {
            JsonNode body = MAPPER.readTree(response.body());
            if (body.isObject()) {
                return body;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:config]

    // --8<-- [start:list]
    /**
     * Returns the ID of the task that created the database. Every create,
     * update and delete runs as a task. The IDs sort by creation time, and
     * sort_order=asc lists the oldest task first.
     */
    static String findCreateTask(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode reply = get(client,
                "/v1/databases/" + DATABASE_ID + "/tasks?sort_order=asc");
        for (JsonNode task : reply.path("tasks")) {
            if (task.path("type").asString("").equals("create")) {
                return task.path("task_id").asString();
            }
        }
        throw new ControlPlaneException("no create task for " + DATABASE_ID);
    }
    // --8<-- [end:list]

    // --8<-- [start:follow]
    /**
     * Prints the log of a task as it grows, until the task finishes, and
     * returns its final status. Each log reply carries last_entry_id, and
     * passing that back as after_entry_id fetches only the newer entries.
     * The status is read before the log, so that once it is final, the log
     * that follows it is complete.
     */
    static String followTask(HttpClient client, String taskId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
        long deadline = System.nanoTime() + FOLLOW_FOR.toNanos();
        String after = "";
        while (true) {
            String status = get(client, path).path("status").asString("unknown");

            String query = after.isEmpty() ? ""
                    : "?after_entry_id=" + URLEncoder.encode(after, StandardCharsets.UTF_8);
            JsonNode log = get(client, path + "/log" + query);
            for (JsonNode entry : log.path("entries")) {
                System.out.println("Log: " + entry.path("message").asString(""));
            }
            String last = log.path("last_entry_id").asString("");
            if (!last.isEmpty()) {
                after = last;
            }

            if (FINAL_STATUSES.contains(status)) {
                return status;
            }
            if (System.nanoTime() >= deadline) {
                throw new ControlPlaneException("task " + taskId + " was still "
                        + status + " after " + FOLLOW_FOR.toSeconds() + " seconds");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }
    // --8<-- [end:follow]

    // --8<-- [start:main]
    public static void main(String[] args) {
        String status;
        try {
            HttpClient client = HttpClient.newHttpClient();
            String taskId = findCreateTask(client);
            System.out.println("Task: create");
            status = followTask(client, taskId);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("Control Plane error: " + e);
            System.exit(1);
            return;
        } catch (ControlPlaneException e) {
            System.err.println("Control Plane error: " + e.getMessage());
            System.exit(1);
            return;
        }

        System.out.println("Status: " + status);
        if (!status.equals("completed")) {
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
