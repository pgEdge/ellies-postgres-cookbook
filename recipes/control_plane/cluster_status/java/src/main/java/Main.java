/*
 * Ellie's Postgres Cookbook
 * Checking the version of the pgEdge Control Plane, its cluster, and the
 * state of each host, using java.net.http and Jackson.
 *
 * These examples are for the Control Plane v0.11.0.
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
import java.time.Duration;
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

    static final Duration TIMEOUT = Duration.ofSeconds(30);

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

    // --8<-- [start:version]
    /** Prints the version of the Control Plane server. */
    static void showVersion(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode version = get(client, "/v1/version").path("version");
        if (!version.isString()) {
            throw new ControlPlaneException("Unexpected response: missing version");
        }
        System.out.println("Version: " + version.stringValue());
    }
    // --8<-- [end:version]

    // --8<-- [start:cluster]
    /**
     * Prints the state of the cluster. A server answers this request only
     * once its cluster has been initialised, and it then reports
     * "available"; the health of the cluster shows in the state of each
     * host.
     */
    static void showCluster(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode state = get(client, "/v1/cluster").path("status").path("state");
        if (!state.isString()) {
            throw new ControlPlaneException("Unexpected response: missing state");
        }
        System.out.println("Cluster: " + state.stringValue());
    }
    // --8<-- [end:cluster]

    // --8<-- [start:hosts]
    /**
     * Lists the hosts in the cluster with their states, and returns whether
     * every host is "healthy". The other states are "degraded",
     * "unreachable" and "unknown".
     */
    static boolean showHosts(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode hosts = get(client, "/v1/hosts").path("hosts");
        if (!hosts.isArray()) {
            throw new ControlPlaneException("Unexpected response: missing hosts");
        }

        System.out.println("Hosts (" + hosts.size() + "):");
        boolean healthy = true;
        for (JsonNode host : hosts) {
            String state = host.path("status").path("state").asString("unknown");
            System.out.println("- " + host.path("id").asString() + ": " + state);
            healthy = healthy && state.equals("healthy");
        }
        return healthy;
    }
    // --8<-- [end:hosts]

    // --8<-- [start:main]
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        boolean healthy;
        try {
            showVersion(client);
            showCluster(client);
            healthy = showHosts(client);
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

        // Report an unhealthy host with the exit status.
        if (!healthy) {
            System.err.println("A host is not healthy");
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
