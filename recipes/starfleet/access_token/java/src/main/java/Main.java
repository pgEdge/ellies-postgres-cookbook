/*
 * Ellie's Postgres Cookbook
 * Exchanging a client ID and secret for a pgEdge Starfleet access token,
 * using java.net.http and Jackson.
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
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String clientId, String clientSecret) {}

    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    /**
     * Reads the API settings from the environment. The client ID and secret
     * have no defaults, so a missing value becomes null, and the token
     * request reports it.
     */
    static Settings settings() {
        return new Settings(
                envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                        .replaceAll("/+$", ""),
                envOr("STARFLEET_CLIENT_ID", null),
                envOr("STARFLEET_CLIENT_SECRET", null));
    }
    // --8<-- [end:config]

    // --8<-- [start:token]
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();

    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();

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

    /**
     * Exchanges the client ID and secret for an access token. The token
     * endpoint belongs to the account API, and accepts the OAuth 2.0 client
     * credentials grant as a JSON body.
     */
    static JsonNode getToken(Settings cfg) throws IOException, InterruptedException {
        if (cfg.clientId() == null || cfg.clientSecret() == null) {
            throw new IllegalStateException(
                    "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }

        String path = "/account/v1/oauth/token";
        HttpRequest request = HttpRequest.newBuilder(URI.create(cfg.baseUrl() + path))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of(
                        "grant_type", "client_credentials",
                        "client_id", cfg.clientId(),
                        "client_secret", cfg.clientSecret()))))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException("POST " + path + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        JsonNode token = JSON.readTree(response.body());
        if (token.path("access_token").asString().isEmpty()) {
            throw new IllegalStateException("the token response has no access token");
        }
        return token;
    }
    // --8<-- [end:token]

    // --8<-- [start:main]
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }

    public static void main(String[] args) {
        try {
            JsonNode token = getToken(settings());
            // Never print the token itself; it grants access to the account.
            System.out.println("Token type: " + token.path("token_type").asString());
            System.out.println("Token length: "
                    + token.get("access_token").asString().length() + " characters");
            System.out.println("Expires in: " + token.path("expires_in").asString()
                    + " seconds");
        // IOException covers failures to connect and error replies from the
        // API, and the client throws InterruptedException if the thread is
        // interrupted.
        } catch (IOException | InterruptedException e) {
            System.err.println("API error: " + describe(e));
            System.exit(1);
        // Jackson throws JacksonException for a reply that is not JSON, and
        // IllegalStateException covers settings and replies that the
        // program cannot use.
        } catch (JacksonException | IllegalStateException e) {
            System.err.println("Error: " + describe(e));
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
