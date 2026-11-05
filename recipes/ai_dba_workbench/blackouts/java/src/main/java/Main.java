/*
 * Ellie's Postgres Cookbook
 * Scheduling a maintenance blackout with the AI DBA Workbench API, using
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
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token, long connectionId) {}

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
        String token = envOr("WORKBENCH_TOKEN", "");
        String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
        if (token.isEmpty() || connectionId.isEmpty()) {
            throw new IOException(
                    "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        if (!connectionId.matches("[0-9]+")) {
            throw new IOException("WORKBENCH_CONNECTION_ID must be a number");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token, Long.parseLong(connectionId));
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
     * Sends a request to the API and returns the JSON reply, or null if the
     * reply has no body. The body may be null. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(Settings cfg, String method, String path,
            Object body) throws IOException, InterruptedException {
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token());
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
        String text = response.body();
        return text.isEmpty() ? null : JSON.readTree(text);
    }
    // --8<-- [end:request]

    // --8<-- [start:create]
    /**
     * Creates a blackout for one monitored server and returns it. The
     * blackout starts a minute ago, so that a small difference between the
     * clocks of this machine and the server cannot leave it inactive, and
     * it ends in one hour. Instant.toString() writes the times in RFC 3339
     * format.
     */
    static JsonNode createBlackout(Settings cfg)
            throws IOException, InterruptedException {
        Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);
        return api(cfg, "POST", "/blackouts", Map.of(
                "scope", "server",
                "connection_id", cfg.connectionId(),
                "reason", "Cookbook maintenance window",
                "start_time", now.minus(Duration.ofMinutes(1)).toString(),
                "end_time", now.plus(Duration.ofHours(1)).toString()));
    }
    // --8<-- [end:create]

    // --8<-- [start:read]
    /** Returns the blackout with the given ID. */
    static JsonNode getBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        return api(cfg, "GET", "/blackouts/" + blackoutId, null);
    }
    // --8<-- [end:read]

    // --8<-- [start:stop]
    /**
     * Stops a blackout that is in progress, which sets its end time to now,
     * and returns the stopped blackout.
     */
    static JsonNode stopBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        return api(cfg, "POST", "/blackouts/" + blackoutId + "/stop", null);
    }
    // --8<-- [end:stop]

    // --8<-- [start:delete]
    /** Deletes a blackout by its ID. */
    static void deleteBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        api(cfg, "DELETE", "/blackouts/" + blackoutId, null);
    }
    // --8<-- [end:delete]

    // --8<-- [start:main]
    /**
     * Guards the blackout that is still to be deleted, which the main
     * thread and the shutdown hook share.
     */
    static final Object LOCK = new Object();
    static Settings pendingCfg;
    static Long pendingId;

    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }

    /**
     * Deletes the blackout if one is still pending, and returns false if
     * that fails. The main thread calls this after a failed step, and the
     * shutdown hook calls it when SIGINT or SIGTERM ends the program first.
     */
    static boolean cleanUp() {
        synchronized (LOCK) {
            if (pendingId == null) {
                return true;
            }
            try {
                deleteBlackout(pendingCfg, pendingId);
                return true;
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: could not delete the blackout: "
                        + describe(e));
                return false;
            } finally {
                pendingId = null;
            }
        }
    }

    public static void main(String[] args) {
        // Java cannot catch a signal with its supported API, but SIGINT and
        // SIGTERM start an orderly shutdown that runs this hook, which
        // deletes the blackout before the program ends.
        Runtime.getRuntime().addShutdownHook(new Thread(Main::cleanUp));

        int status = 0;
        try {
            Settings cfg = settings();

            // Hold the lock until the ID is recorded, so that a signal
            // during the create call cannot leave the blackout behind.
            JsonNode created;
            long blackoutId;
            synchronized (LOCK) {
                created = createBlackout(cfg);
                blackoutId = created.get("id").asLong();
                pendingCfg = cfg;
                pendingId = blackoutId;
            }
            System.out.println("Created a blackout for the server (active: "
                    + created.get("is_active").asBoolean() + ")");

            JsonNode blackout = getBlackout(cfg, blackoutId);
            System.out.println("Read the blackout back (active: "
                    + blackout.get("is_active").asBoolean() + ")");

            JsonNode stopped = stopBlackout(cfg, blackoutId);
            boolean active = stopped.get("is_active").asBoolean();
            System.out.println("Stopped the blackout (active: " + active + ")");
            if (active) {
                throw new IOException("The blackout is still active");
            }

            synchronized (LOCK) {
                deleteBlackout(cfg, blackoutId);
                pendingId = null;
            }
            System.out.println("Deleted the blackout");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }

        // Delete the blackout whether or not a later step failed, so that a
        // failed run does not leave alerts suppressed.
        if (!cleanUp()) {
            status = 1;
        }
        System.exit(status);
    }
    // --8<-- [end:main]
}
