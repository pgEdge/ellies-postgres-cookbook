/*
 * Ellie's Postgres Cookbook
 * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
 * Starfleet Managed API offers, using java.net.http and Jackson.
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
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
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
     * Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
     * throws an IOException that includes the message from the API.
     */
    static JsonNode request(HttpRequest request, String path)
            throws IOException, InterruptedException {
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException(request.method() + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        return JSON.readTree(response.body());
    }

    /**
     * Exchanges the client ID and secret for an access token, which the
     * Managed API accepts as a bearer token until it expires.
     */
    static String getToken(Settings cfg) throws IOException, InterruptedException {
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
        return request(request, path).get("access_token").asString();
    }
    // --8<-- [end:token]

    // --8<-- [start:api]
    /**
     * Sends an authenticated GET request to the Managed API and returns the
     * decoded JSON reply. The query, if there is one, follows the path.
     */
    static JsonNode apiGet(Settings cfg, String token, String path, String query)
            throws IOException, InterruptedException {
        String url = cfg.baseUrl() + "/managed/v1" + path
                + (query.isEmpty() ? "" : "?" + query);
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + token)
                .GET()
                .build();
        return request(request, path);
    }
    // --8<-- [end:api]

    // --8<-- [start:regions]
    /** Returns the identifiers of the regions that can host a database. */
    static List<String> listRegions(Settings cfg, String token)
            throws IOException, InterruptedException {
        List<String> regions = new ArrayList<>();
        for (JsonNode region : apiGet(cfg, token, "/regions", "")) {
            regions.add(region.get("region").asString());
        }
        return regions;
    }
    // --8<-- [end:regions]

    // --8<-- [start:sizes]
    /** Returns a description of each size, smallest first. */
    static List<String> listSizes(Settings cfg, String token)
            throws IOException, InterruptedException {
        // The pricing option asks the API to include each size's price,
        // which takes a little longer because the API looks it up from
        // billing.
        List<String> sizes = new ArrayList<>();
        for (JsonNode size : apiGet(cfg, token, "/sizes", "include=pricing")) {
            String line = size.get("name").asString() + ": "
                    + size.get("connections").asLong() + " connections, "
                    + size.get("storage_size").asString() + " storage";
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as
            // cents. Locale.ROOT keeps the decimal point a full stop.
            JsonNode price = size.get("pricing");
            if (price != null && !price.isNull()) {
                line += String.format(Locale.ROOT, ", %.2f %s per %s",
                        price.get("price_amount").asLong() / 100.0,
                        price.get("currency").asString(),
                        price.get("billing_interval").asString());
            }
            sizes.add(line);
        }
        return sizes;
    }
    // --8<-- [end:sizes]

    // --8<-- [start:versions]
    /**
     * Returns the PostgreSQL major versions, newest first, marking the one
     * that a new database gets by default.
     */
    static List<String> listVersions(Settings cfg, String token)
            throws IOException, InterruptedException {
        List<String> versions = new ArrayList<>();
        for (JsonNode version : apiGet(cfg, token, "/pg-versions", "")) {
            versions.add(version.get("version").asString()
                    + (version.path("default").asBoolean() ? " (default)" : ""));
        }
        return versions;
    }
    // --8<-- [end:versions]

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
            Settings cfg = settings();
            String token = getToken(cfg);

            System.out.println("Regions:");
            for (String region : listRegions(cfg, token)) {
                System.out.println("  " + region);
            }

            System.out.println("Sizes (smallest first):");
            for (String size : listSizes(cfg, token)) {
                System.out.println("  " + size);
            }

            System.out.println("PostgreSQL versions:");
            for (String version : listVersions(cfg, token)) {
                System.out.println("  " + version);
            }
        // IOException covers failures to connect and error replies from the
        // API, and the client throws InterruptedException if the thread is
        // interrupted.
        } catch (IOException | InterruptedException e) {
            System.err.println("API error: " + describe(e));
            System.exit(1);
        // Jackson throws JacksonException for a reply that is not JSON, and
        // IllegalStateException covers settings that are missing.
        } catch (JacksonException | IllegalStateException e) {
            System.err.println("Error: " + describe(e));
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
