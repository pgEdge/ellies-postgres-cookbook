/*
 * Ellie's Postgres Cookbook
 * Querying metrics and top queries with the AI DBA Workbench API, using
 * java.net.http and Jackson.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.io.IOException;
import java.math.BigDecimal;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.stream.Collectors;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token, String connectionId) {}

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
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token, connectionId);
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
     * Sends a GET request to the API, with the parameters in the query
     * string, and returns the JSON reply. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(Settings cfg, String path, Map<String, String> params)
            throws IOException, InterruptedException {
        String query = params.entrySet().stream()
                .map(p -> URLEncoder.encode(p.getKey(), StandardCharsets.UTF_8)
                        + "=" + URLEncoder.encode(p.getValue(),
                                StandardCharsets.UTF_8))
                .collect(Collectors.joining("&"));
        HttpRequest request = HttpRequest
                .newBuilder(URI.create(
                        cfg.baseUrl() + "/api/v1" + path + "?" + query))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token())
                .GET()
                .build();

        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException("GET " + path + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        return JSON.readTree(response.body());
    }
    // --8<-- [end:request]

    // --8<-- [start:query_metrics]
    /**
     * Returns a number as plain decimal text, without an exponent or
     * trailing zeros, as the other languages print it.
     */
    static String plain(double value) {
        return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
    }

    /**
     * Prints one line for each series that the pg_stat_database probe
     * collected over the last hour, in six buckets: the metric, the number
     * of points, and the latest value.
     */
    static void queryMetrics(Settings cfg)
            throws IOException, InterruptedException {
        // A LinkedHashMap keeps the parameters in the order given.
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("probe_name", "pg_stat_database");
        params.put("time_range", "1h");
        params.put("buckets", "6");
        params.put("metrics", "numbackends,xact_commit");

        JsonNode series = api(cfg, "/metrics/query", params);
        if (series.isEmpty()) {
            throw new IOException(
                    "The Workbench returned no series; has the collector run yet?");
        }
        for (JsonNode s : series) {
            JsonNode points = s.path("data");
            String name = s.get("name").asString();
            if (points.isEmpty()) {
                System.out.println(name + ": no data");
                continue;
            }
            double latest = points.get(points.size() - 1).get("value")
                    .asDouble();
            System.out.println(name + ": " + points.size()
                    + " points, latest " + plain(latest));
        }
    }
    // --8<-- [end:query_metrics]

    // --8<-- [start:top_queries]
    /**
     * Prints the queries that have used the most execution time, as the
     * pg_stat_statements extension on the monitored server recorded them.
     * The query text is cut to 50 characters on one line.
     */
    static void topQueries(Settings cfg)
            throws IOException, InterruptedException {
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("limit", "5");
        params.put("order_by", "total_exec_time");
        params.put("exclude_collector", "true");

        JsonNode queries = api(cfg, "/metrics/top-queries", params);
        if (queries.isEmpty()) {
            System.out.println(
                    "No statements recorded (is pg_stat_statements installed?)");
            return;
        }

        System.out.println("Top queries by total execution time:");
        int rank = 1;
        for (JsonNode q : queries) {
            String text = q.get("query").asString().strip()
                    .replaceAll("\\s+", " ");
            // Count characters, not UTF-16 units, when cutting the text.
            if (text.codePointCount(0, text.length()) > 50) {
                text = text.substring(0, text.offsetByCodePoints(0, 50));
            }
            double mean = Math.round(
                    q.get("mean_exec_time").asDouble() * 100) / 100.0;
            System.out.println(rank + ". " + q.get("calls").asLong()
                    + " calls, " + plain(mean) + " ms mean: " + text);
            rank++;
        }
    }
    // --8<-- [end:top_queries]

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
        try {
            Settings cfg = settings();
            queryMetrics(cfg);
            topQueries(cfg);
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }
        System.exit(status);
    }
    // --8<-- [end:main]
}
