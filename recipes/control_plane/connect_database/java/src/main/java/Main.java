/*
 * Ellie's Postgres Cookbook
 * Finding the address of a pgEdge Control Plane database and connecting
 * to it, using java.net.http, Jackson and pgJDBC.
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
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.Properties;
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

    // The password has no default; the Control Plane never returns it, so
    // it comes from whoever created the database user.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
    static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);

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

    // --8<-- [start:find]
    /** The settings for connecting to one instance. */
    record Instance(String node, String host, int port, String database) {
    }

    /**
     * Returns the connection settings for the first instance of the
     * database that is available. Each instance runs one node of the
     * database, and its connection_info holds the addresses and port that
     * clients use.
     */
    static Instance findInstance(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode database = get(client, "/v1/databases/" + DATABASE_ID);
        for (JsonNode instance : database.path("instances")) {
            JsonNode info = instance.path("connection_info");
            if (instance.path("state").asString("").equals("available")
                    && info.path("addresses").size() > 0) {
                return new Instance(
                        instance.path("node_name").asString(),
                        info.path("addresses").get(0).asString(),
                        info.path("port").asInt(),
                        database.path("spec").path("database_name").asString());
            }
        }
        throw new ControlPlaneException("no available instance of " + DATABASE_ID);
    }
    // --8<-- [end:find]

    // --8<-- [start:connect]
    /**
     * Connects to the instance, and returns the name of the database and
     * the version of the Spock extension.
     */
    static String[] query(Instance instance) throws SQLException {
        Properties props = new Properties();
        props.setProperty("user", DATABASE_USER);
        props.setProperty("password", DATABASE_PASSWORD);
        props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
        String url = "jdbc:postgresql://" + instance.host() + ":"
                + instance.port() + "/" + instance.database();

        // try-with-resources closes the connection and statement when the
        // block exits, whether or not a query failed.
        try (Connection conn = DriverManager.getConnection(url, props);
             Statement stmt = conn.createStatement()) {
            String database;
            try (ResultSet rs = stmt.executeQuery("SELECT current_database()")) {
                rs.next();
                database = rs.getString(1);
            }
            try (ResultSet rs = stmt.executeQuery(
                    "SELECT extversion FROM pg_extension WHERE extname = 'spock'")) {
                return new String[] {
                    database, rs.next() ? rs.getString(1) : "not installed"
                };
            }
        }
    }
    // --8<-- [end:connect]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (DATABASE_PASSWORD == null) {
            System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            System.exit(1);
        }

        Instance instance;
        try {
            instance = findInstance(HttpClient.newHttpClient());
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
        System.out.println("Connecting to node " + instance.node());

        try {
            String[] result = query(instance);
            System.out.println("Connected to database " + result[0]);
            System.out.println("Spock: " + result[1]);
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
