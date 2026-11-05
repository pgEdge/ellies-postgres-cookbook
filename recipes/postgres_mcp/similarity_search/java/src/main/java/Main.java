/*
 * Ellie's Postgres Cookbook
 * Searching by meaning through the pgEdge Postgres MCP Server, using
 * java.net.http and Jackson.
 *
 * These examples are for pgEdge Postgres MCP Server 1.1.0.
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
            envOr("MCP_URL", "http://localhost:8080").replaceAll("/+$", "");
    static final String TOKEN = envOr("MCP_TOKEN", "");

    // The server turns the query into an embedding before it searches,
    // which can take a while if the embedding model has to load first, so
    // the timeout is longer than in the other recipes.
    static final Duration TIMEOUT = Duration.ofSeconds(90);

    static final String QUERY = "a gift for an amateur astronomer";

    /** Thrown when the MCP Server rejects a request or replies oddly. */
    static class McpException extends Exception {
        McpException(String message) {
            super(message);
        }
    }

    // A client and a mapper are safe to share, so the program creates
    // only one of each.
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .build();
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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

    /** Parses a reply as a JSON object, or returns null if it is not one. */
    static JsonNode parseObject(String text) {
        try {
            JsonNode node = MAPPER.readTree(text);
            return node.isObject() ? node : null;
        } catch (JacksonException e) {
            return null;
        }
    }

    /**
     * Calls a tool with tools/call and returns the text of its reply. The
     * server answers a JSON-RPC error with HTTP status 200, and a tool that
     * fails returns a normal result with isError set, so the method checks
     * for both as well as the HTTP status.
     */
    static String callTool(String name, Map<String, Object> arguments)
            throws IOException, InterruptedException, McpException {
        String message = MAPPER.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", "tools/call",
                "params", Map.of("name", name, "arguments", arguments)));
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + TOKEN)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(message))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException(name + " failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode reply = parseObject(response.body());
        if (reply == null || !(reply.has("result") || reply.has("error"))) {
            throw new McpException(name + " failed: unexpected response: "
                    + shorten(response.body()));
        }
        if (reply.has("error")) {
            throw new McpException(name + " failed: "
                    + reply.path("error").path("message").asString());
        }
        JsonNode result = reply.path("result");
        JsonNode text = result.path("content").path(0).path("text");
        if (!text.isString()) {
            throw new McpException(name + " failed: unexpected result: "
                    + shorten(response.body()));
        }
        if (result.path("isError").asBoolean(false)) {
            throw new McpException(name + " failed: " + text.stringValue());
        }
        return text.stringValue();
    }
    // --8<-- [end:config]

    // --8<-- [start:search]
    /**
     * Searches the product descriptions for the query, and prints the
     * number of results and the name of the product that matches it most
     * closely. similarity_search finds the closest rows by vector distance,
     * and then reorders them, mixing in a keyword score and favouring
     * variety, so the first result in the reply is not always the closest.
     * Each result has a line such as "Source:
     * cookbook_mcp.products.description (vector search rank: #1, chunk:
     * 1)"; the method picks the result ranked first by the vector search,
     * whose text follows the first blank line after it. Every description
     * starts with the product's name and a colon.
     */
    static void search() throws IOException, InterruptedException, McpException {
        String text = callTool("similarity_search", Map.of(
                "table_name", "cookbook_mcp.products",
                "query_text", QUERY,
                "top_n", 3));
        System.out.println("Query: " + QUERY);
        String[] lines = text.split("\n", -1);
        int count = 0;
        for (String line : lines) {
            if (line.matches("Result \\d+/\\d+")) {
                count++;
            }
        }
        System.out.println("Results: " + count);

        int source = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("Source: ")
                    && lines[i].endsWith("(vector search rank: #1, chunk: 1)")) {
                source = i;
                break;
            }
        }
        String best = "";
        if (source >= 0) {
            for (int i = source + 1; i + 1 < lines.length; i++) {
                if (lines[i].isEmpty()) {
                    best = lines[i + 1];
                    break;
                }
            }
        }
        int colon = best.indexOf(": ");
        if (colon < 0) {
            throw new McpException("The reply had no closest match: " + shorten(text));
        }
        System.out.println("Best match: " + best.substring(0, colon));
    }
    // --8<-- [end:search]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            search();
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("MCP Server error: " + e);
            System.exit(1);
        } catch (McpException e) {
            System.err.println("MCP Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
