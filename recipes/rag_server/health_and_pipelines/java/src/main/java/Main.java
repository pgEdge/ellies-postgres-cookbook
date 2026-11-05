/*
 * Ellie's Postgres Cookbook
 * Checking the health of the pgEdge RAG Server and listing its pipelines,
 * using java.net.http and Jackson.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
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
            envOr("RAG_SERVER_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");

    // None of these endpoints calls a language model, but the health
    // check contacts each provider, so allow it some time.
    static final Duration TIMEOUT = Duration.ofSeconds(30);

    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }

    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    /** Fetches a path from the server, and returns the decoded reply. */
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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

    static JsonNode get(HttpClient client, String path)
            throws IOException, InterruptedException, RagException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(client, request);
        if (response.statusCode() >= 400) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + shorten(response.body()));
        }
        try {
            JsonNode body = MAPPER.readTree(response.body());
            if (body.isObject()) {
                return body;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new RagException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:config]

    // --8<-- [start:live]
    /**
     * Checks that the server process is running. The /v1/live endpoint is
     * cheap and calls nothing else, so it suits a frequent liveness probe.
     */
    static void checkLive(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode body = get(client, "/v1/live");
        if (!"ok".equals(body.path("status").asString())) {
            throw new RagException("Unexpected response: " + body);
        }
        System.out.println("Live: ok");
    }
    // --8<-- [end:live]

    // --8<-- [start:health]
    /** Describes whether a language model provider answered the check. */
    static String describeProvider(JsonNode provider) {
        if (provider.path("reachable").asBoolean()) {
            return "reachable";
        }
        return "unreachable (" + provider.path("error").asString("unknown") + ")";
    }

    /**
     * Checks whether each pipeline can reach its language model providers.
     * The /v1/health endpoint answers with HTTP 200 even when a provider is
     * down, so the status field is the thing to check: it is "healthy" or
     * "degraded". Prints the report, and returns whether the server is
     * healthy.
     */
    static boolean checkHealth(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode body = get(client, "/v1/health");
        JsonNode status = body.path("status");
        if (!status.isString()) {
            throw new RagException("Unexpected response: " + body);
        }

        System.out.println("Health: " + status.stringValue());
        // path() gives a missing node, which holds no elements, when the
        // reply lists no pipelines.
        for (JsonNode pipeline : body.path("pipelines")) {
            String embedding = describeProvider(pipeline.path("embedding"));
            String completion = describeProvider(pipeline.path("completion"));
            System.out.println("- " + pipeline.path("name").asString()
                    + ": embedding " + embedding + ", completion " + completion);
        }
        return status.stringValue().equals("healthy");
    }
    // --8<-- [end:health]

    // --8<-- [start:pipelines]
    /**
     * Lists the pipelines that the server offers, with their descriptions.
     */
    static void listPipelines(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode pipelines = get(client, "/v1/pipelines").path("pipelines");
        if (!pipelines.isArray()) {
            throw new RagException("Unexpected response: missing pipelines");
        }

        System.out.println("Pipelines (" + pipelines.size() + "):");
        for (JsonNode pipeline : pipelines) {
            String description = pipeline.path("description").asString("");
            if (description.isEmpty()) {
                description = "(no description)";
            }
            System.out.println("- " + pipeline.path("name").asString()
                    + ": " + description);
        }
    }
    // --8<-- [end:pipelines]

    // --8<-- [start:main]
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        boolean healthy;
        try {
            checkLive(client);
            healthy = checkHealth(client);
            listPipelines(client);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
            return;
        } catch (RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
            return;
        }

        // A degraded server still answers with HTTP 200, so report it with
        // the exit status.
        if (!healthy) {
            System.err.println("RAG Server is not healthy");
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
