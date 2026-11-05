/*
 * Ellie's Postgres Cookbook
 * Registering a server to monitor with the AI DBA Workbench API, using
 * java.net.http and Jackson.
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
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    static final String SERVER_NAME = "cookbook-register-server";

    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String username, String password,
            String connectionId, String serverPassword) {}

    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    /** Reads the settings from the environment. */
    static Settings settings() throws IOException {
        String username = envOr("WORKBENCH_USERNAME", "");
        String password = envOr("WORKBENCH_PASSWORD", "");
        String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
        if (username.isEmpty() || password.isEmpty()
                || connectionId.isEmpty()) {
            throw new IOException("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, "
                    + "and WORKBENCH_CONNECTION_ID must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        // The Workbench refuses to register a server without a password,
        // even one that uses trust authentication, so fall back to a
        // placeholder.
        String serverPassword =
                envOr("PGPASSWORD", "unused-with-trust-authentication");
        return new Settings(baseUrl, username, password, connectionId,
                serverPassword);
    }
    // --8<-- [end:config]

    // --8<-- [start:request]
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();

    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
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

    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();

    /**
     * Sends a request to the API and returns the response. The token and
     * the body may be null. A request that the server rejects throws an
     * error that includes the message from the server.
     */
    static HttpResponse<String> api(String method, String baseUrl,
            String path, String token, Object body)
            throws IOException, InterruptedException {
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(baseUrl + "/api/v1" + path))
                .timeout(Duration.ofSeconds(30));
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }

        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new IOException(method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        return response;
    }

    /** Sends a request to the API and returns the JSON reply. */
    static JsonNode apiJson(String method, String baseUrl, String path,
            String token, Object body)
            throws IOException, InterruptedException {
        return JSON.readTree(api(method, baseUrl, path, token, body).body());
    }
    // --8<-- [end:request]

    // --8<-- [start:login]
    /** Matches the session_token cookie in a Set-Cookie header. */
    static final Pattern SESSION_COOKIE =
            Pattern.compile("^session_token=([^;]*)");

    /**
     * Logs in and returns the session token. The server returns the token
     * in a session_token cookie, not in the body of the reply.
     */
    static String login(String baseUrl, String username, String password)
            throws IOException, InterruptedException {
        HttpResponse<String> response = api("POST", baseUrl, "/auth/login",
                null, Map.of("username", username, "password", password));
        for (String cookie : response.headers().allValues("Set-Cookie")) {
            Matcher match = SESSION_COOKIE.matcher(cookie);
            if (match.find()) {
                return match.group(1);
            }
        }
        throw new IOException("The login reply had no session_token cookie");
    }
    // --8<-- [end:login]

    // --8<-- [start:lookup]
    /**
     * Returns the details of an existing connection, which the program
     * uses as the address of the server to register.
     */
    static JsonNode getConnection(String baseUrl, String session,
            String connectionId) throws IOException, InterruptedException {
        return apiJson("GET", baseUrl, "/connections/" + connectionId,
                session, null);
    }
    // --8<-- [end:lookup]

    // --8<-- [start:register]
    /**
     * Registers a server and returns the ID of the new connection. The
     * address comes from an existing connection. The request must include
     * a password, and a description, which the server needs in version
     * 1.0.0.
     */
    static long registerServer(String baseUrl, String session, String name,
            JsonNode template, String password)
            throws IOException, InterruptedException {
        ObjectNode body = JSON.createObjectNode()
                .put("name", name)
                .put("description", "Registered by the cookbook");
        // Copy the address from the existing connection; set() writes a
        // JSON null for a field that the connection lacks.
        for (String field : new String[] {
                "host", "port", "database_name", "username", "ssl_mode"}) {
            body.set(field, template.get(field));
        }
        body.put("password", password)
                .put("is_monitored", true)
                .put("is_shared", false);

        JsonNode created = apiJson("POST", baseUrl, "/connections", session,
                body);
        return created.get("id").asLong();
    }
    // --8<-- [end:register]

    // --8<-- [start:list]
    /**
     * Returns the named connection from the list, or null if the list has
     * no such connection.
     */
    static JsonNode findConnection(String baseUrl, String session,
            String name) throws IOException, InterruptedException {
        for (JsonNode connection
                : apiJson("GET", baseUrl, "/connections", session, null)) {
            if (name.equals(connection.get("name").asString())) {
                return connection;
            }
        }
        return null;
    }
    // --8<-- [end:list]

    // --8<-- [start:delete]
    /** Deletes a connection by its ID. */
    static void deleteConnection(String baseUrl, String session,
            long connectionId) throws IOException, InterruptedException {
        api("DELETE", baseUrl, "/connections/" + connectionId, session,
                null);
    }
    // --8<-- [end:delete]

    // --8<-- [start:main]
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }

    public static void main(String[] args) {
        int status = 0;
        String baseUrl = null;
        String session = null;
        Long newId = null;
        try {
            Settings settings = settings();
            baseUrl = settings.baseUrl();

            session = login(baseUrl, settings.username(),
                    settings.password());
            JsonNode template = getConnection(baseUrl, session,
                    settings.connectionId());

            newId = registerServer(baseUrl, session, SERVER_NAME, template,
                    settings.serverPassword());
            System.out.println("Registered the server '" + SERVER_NAME + "'");

            JsonNode found = findConnection(baseUrl, session, SERVER_NAME);
            if (found == null) {
                throw new IOException(
                        "The new connection is missing from the list");
            }
            System.out.println("Found '" + SERVER_NAME
                    + "' in the list (monitored: "
                    + found.get("is_monitored").asBoolean() + ")");

            deleteConnection(baseUrl, session, newId);
            newId = null;
            System.out.println("Deleted the connection");

            if (findConnection(baseUrl, session, SERVER_NAME) != null) {
                throw new IOException("The connection is still in the list");
            }
            System.out.println("The connection is no longer in the list");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        } finally {
            // Delete the connection whether or not a later step failed, so
            // that a failed run does not leave a server registered. The
            // finally block also runs for an error that the catch does not
            // handle.
            if (newId != null) {
                try {
                    deleteConnection(baseUrl, session, newId);
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println(
                            "Error: could not delete the connection: "
                            + describe(e));
                    status = 1;
                }
            }
        }
        System.exit(status);
    }
    // --8<-- [end:main]
}
