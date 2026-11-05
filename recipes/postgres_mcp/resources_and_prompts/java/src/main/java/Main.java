/*
 * Ellie's Postgres Cookbook
 * Reading resources and prompts from the pgEdge Postgres MCP Server, using
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
import java.util.ArrayList;
import java.util.List;
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

    static final Duration TIMEOUT = Duration.ofSeconds(30);

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
     * Sends a JSON-RPC request and returns its result. The server answers a
     * JSON-RPC error with HTTP status 200, so the method checks the reply
     * for an error member as well as the HTTP status.
     */
    static JsonNode rpc(String method, Map<String, Object> params)
            throws IOException, InterruptedException, McpException {
        String message = MAPPER.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + TOKEN)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(message))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException(method + " failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode reply = parseObject(response.body());
        if (reply == null || !(reply.has("result") || reply.has("error"))) {
            throw new McpException(method + " failed: unexpected response: "
                    + shorten(response.body()));
        }
        if (reply.has("error")) {
            throw new McpException(method + " failed: "
                    + reply.path("error").path("message").asString());
        }
        return reply.get("result");
    }
    // --8<-- [end:config]

    // --8<-- [start:resources]
    /**
     * Lists the resources that the server offers, and then reads
     * pg://system_info, which describes the PostgreSQL server. The contents
     * of a resource are text, which for this one holds a JSON object, so
     * the method parses the text a second time. version_number is a string
     * such as "180006", from which integer division by 10000 gives the
     * major version.
     */
    static void readSystemInfo() throws IOException, InterruptedException, McpException {
        List<String> uris = new ArrayList<>();
        for (JsonNode resource : rpc("resources/list", Map.of()).path("resources")) {
            uris.add(resource.path("uri").asString(""));
        }
        System.out.println("Resources: " + String.join(", ", uris));

        JsonNode result = rpc("resources/read", Map.of("uri", "pg://system_info"));
        JsonNode info = parseObject(
                result.path("contents").path(0).path("text").asString(""));
        if (info == null || !info.path("allow_writes").isBoolean()) {
            throw new McpException("Unexpected result: " + shorten(result.toString()));
        }
        int versionNumber;
        try {
            versionNumber = Integer.parseInt(info.path("version_number").asString(""));
        } catch (NumberFormatException e) {
            throw new McpException("Unexpected version number: " + info.path("version_number"));
        }
        System.out.println("PostgreSQL major version: " + versionNumber / 10000);
        System.out.println("Writes allowed: " + info.path("allow_writes").booleanValue());
    }
    // --8<-- [end:resources]

    // --8<-- [start:prompts]
    /**
     * Lists the prompts that the server offers, and then fetches
     * explore-database, which takes no arguments. A prompt is a set of
     * messages, ready to hand to a language model, that guide it through a
     * task with the server's tools.
     */
    static void readPrompts() throws IOException, InterruptedException, McpException {
        List<String> names = new ArrayList<>();
        for (JsonNode prompt : rpc("prompts/list", Map.of()).path("prompts")) {
            names.add(prompt.path("name").asString(""));
        }
        System.out.println("Prompts: " + String.join(", ", names));

        JsonNode prompt = rpc("prompts/get",
                Map.of("name", "explore-database", "arguments", Map.of()));
        JsonNode role = prompt.path("messages").path(0).path("role");
        if (!role.isString()) {
            throw new McpException("Unexpected result: " + shorten(prompt.toString()));
        }
        System.out.println("explore-database: " + prompt.path("description").asString(""));
        System.out.println("First message role: " + role.stringValue());
    }
    // --8<-- [end:prompts]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            readSystemInfo();
            readPrompts();
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
