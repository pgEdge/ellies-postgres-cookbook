/*
 * Ellie's Postgres Cookbook
 * Connecting to the pgEdge Postgres MCP Server, using java.net.http and
 * Jackson.
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

    /** Posts a JSON-RPC message to the MCP endpoint with a token. */
    static HttpResponse<String> post(String token, Map<String, Object> message)
            throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        MAPPER.writeValueAsString(message)))
                .build();
        return send(request);
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
        HttpResponse<String> response = post(TOKEN, Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
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

    // --8<-- [start:health]
    /** Checks that the server is running. The /health endpoint needs no token. */
    static void checkHealth() throws IOException, InterruptedException, McpException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/health"))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException("Health check failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode body = parseObject(response.body());
        if (body == null || !"ok".equals(body.path("status").asString(""))) {
            throw new McpException("Unexpected response: " + shorten(response.body()));
        }
        System.out.println("Health: ok");
    }
    // --8<-- [end:health]

    // --8<-- [start:initialize]
    /**
     * Introduces the client to the server, and prints the server's name and
     * version and the protocol revision that the server chose. The server
     * accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers
     * a revision it does not know with one that it does, so the client
     * checks the answer. The notifications/initialized message then
     * completes the handshake; it is a notification, with no id, so the
     * server replies with HTTP 202 and no body.
     */
    static void initialize() throws IOException, InterruptedException, McpException {
        JsonNode result = rpc("initialize", Map.of(
                "protocolVersion", "2025-06-18",
                "capabilities", Map.of(),
                "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
        JsonNode info = result.path("serverInfo");
        if (!info.path("name").isString() || !info.path("version").isString()) {
            throw new McpException("Unexpected result: " + result);
        }
        System.out.println("Server: " + info.path("name").stringValue()
                + " " + info.path("version").stringValue());
        String protocol = result.path("protocolVersion").asString("");
        if (!protocol.equals("2025-06-18")) {
            throw new McpException("The server chose protocol version " + protocol);
        }
        System.out.println("Protocol version: " + protocol);

        HttpResponse<String> response = post(TOKEN, Map.of(
                "jsonrpc", "2.0", "method", "notifications/initialized"));
        if (response.statusCode() != 202) {
            throw new McpException("notifications/initialized failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
    }
    // --8<-- [end:initialize]

    // --8<-- [start:wrong_token]
    /**
     * Sends a request with a token that the server does not know, and
     * prints the HTTP status and the server's message, which is a JSON
     * object with an error member rather than a JSON-RPC reply.
     */
    static void wrongToken() throws IOException, InterruptedException, McpException {
        HttpResponse<String> response = post("not-a-real-token", Map.of(
                "jsonrpc", "2.0", "id", 1, "method", "tools/list",
                "params", Map.of()));
        if (response.statusCode() != 401) {
            throw new McpException("Expected HTTP 401 for a wrong token, but got "
                    + response.statusCode());
        }
        JsonNode body = parseObject(response.body());
        String message = body == null ? "" : body.path("error").asString("");
        if (message.isEmpty()) {
            message = "no message";
        }
        System.out.println("Wrong token: HTTP " + response.statusCode() + ", " + message);
    }
    // --8<-- [end:wrong_token]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            checkHealth();
            initialize();
            wrongToken();
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
