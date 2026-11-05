/*
 * Ellie's Postgres Cookbook
 * Authenticating with the AI DBA Workbench API, using java.net.http and
 * Jackson.
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
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String username, String password) {}

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
        if (username.isEmpty() || password.isEmpty()) {
            throw new IOException(
                    "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, username, password);
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

    // --8<-- [start:user_info]
    /** Returns the user that a token belongs to, with its superuser flag. */
    static String userInfo(String baseUrl, String token)
            throws IOException, InterruptedException {
        JsonNode info = JSON.readTree(
                api("GET", baseUrl, "/user/info", token, null).body());
        return info.get("username").asString() + " (superuser: "
                + info.get("is_superuser").asBoolean() + ")";
    }
    // --8<-- [end:user_info]

    // --8<-- [start:create_token]
    /** The ID and the value of a new API token. */
    record CreatedToken(long id, String token) {}

    /**
     * Creates an API token for a user and returns its ID and its value.
     * The server shows the value only once. The token expires after an
     * hour.
     */
    static CreatedToken createToken(String baseUrl, String session,
            String owner, String annotation)
            throws IOException, InterruptedException {
        JsonNode created = JSON.readTree(api("POST", baseUrl, "/rbac/tokens",
                session, Map.of(
                        "owner_username", owner,
                        "annotation", annotation,
                        "expires_in", "1h")).body());
        return new CreatedToken(created.get("id").asLong(),
                created.get("token").asString());
    }
    // --8<-- [end:create_token]

    // --8<-- [start:delete_token]
    /** Deletes an API token by its ID. */
    static void deleteToken(String baseUrl, String session, long tokenId)
            throws IOException, InterruptedException {
        api("DELETE", baseUrl, "/rbac/tokens/" + tokenId, session, null);
    }
    // --8<-- [end:delete_token]

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
        CreatedToken created = null;
        try {
            Settings settings = settings();
            baseUrl = settings.baseUrl();

            session = login(baseUrl, settings.username(),
                    settings.password());
            System.out.println("Logged in with a session token");
            System.out.println("Session token belongs to "
                    + userInfo(baseUrl, session));

            created = createToken(baseUrl, session, settings.username(),
                    "cookbook-authenticate");
            System.out.println(
                    "Created the API token 'cookbook-authenticate'");
            System.out.println("API token belongs to "
                    + userInfo(baseUrl, created.token()));
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        } finally {
            // Delete the token whether or not a later step failed, so that a
            // failed run does not leave a token behind. The finally block also
            // runs for an error that the catch does not handle.
            if (created != null) {
                try {
                    deleteToken(baseUrl, session, created.id());
                    System.out.println("Deleted the API token");
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println("Error: could not delete the token: "
                            + describe(e));
                    status = 1;
                }
            }
        }
        System.exit(status);
    }
    // --8<-- [end:main]
}
