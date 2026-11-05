/*
 * Ellie's Postgres Cookbook
 * Running read-only queries through the pgEdge Postgres MCP Server, using
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

    static final Duration TIMEOUT = Duration.ofSeconds(30);

    /** Thrown when the MCP Server rejects a request or replies oddly. */
    static class McpException extends Exception {
        McpException(String message) {
            super(message);
        }
    }

    /** The text of a tool's reply, and whether the tool failed. */
    record ToolResult(String text, boolean failed) {
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
     * Calls a tool with tools/call and returns the text of its reply and
     * whether the tool failed, which it reports by setting isError. The
     * server answers a JSON-RPC error with HTTP status 200, so the method
     * checks the reply for an error member as well as the HTTP status.
     */
    static ToolResult callTool(String name, Map<String, Object> arguments)
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
        return new ToolResult(text.stringValue(), result.path("isError").asBoolean(false));
    }
    // --8<-- [end:config]

    // --8<-- [start:select]
    /**
     * Runs a SELECT with query_database, and prints the column names and
     * each row. The reply repeats the query, with the LIMIT that the server
     * adds, and then has a line such as "Results (3 rows):", a header line,
     * and one line for each row, with the values separated by tabs. The
     * server writes a tab or a newline inside a value as \t or \n, and a
     * NULL as an empty string.
     */
    static void selectCheapProducts() throws IOException, InterruptedException, McpException {
        ToolResult result = callTool("query_database", Map.of(
                "query", "SELECT name, price FROM cookbook_mcp.products "
                        + "WHERE price < 100 ORDER BY price"));
        if (result.failed()) {
            throw new McpException("query_database failed: " + result.text());
        }
        String[] lines = result.text().split("\n");
        int start = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("Results ")) {
                start = i;
                break;
            }
        }
        if (start < 0 || start + 1 >= lines.length) {
            throw new McpException("Unexpected reply: " + shorten(result.text()));
        }
        System.out.println("Columns: " + lines[start + 1].replace("\t", ", "));
        for (int i = start + 2; i < lines.length; i++) {
            if (!lines[i].isEmpty()) {
                System.out.println("Row: " + lines[i].replace("\t", ", "));
            }
        }
    }
    // --8<-- [end:select]

    // --8<-- [start:insert]
    /**
     * Tries to add a row. query_database runs every query in a read-only
     * transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
     * 25006, and the tool returns the error with isError set to true. The
     * INSERT leaves out id, which the table requires, so that even a server
     * that allows writes would refuse it rather than save a row. That is
     * why the method checks for the read-only error itself rather than
     * for any error, and fails if the write succeeds or fails for another
     * reason. It prints only the last line of the error, which holds
     * PostgreSQL's message, because some errors start with the query.
     */
    static void tryInsert() throws IOException, InterruptedException, McpException {
        ToolResult result = callTool("query_database", Map.of(
                "query", "INSERT INTO cookbook_mcp.products "
                        + "(name, category, price, in_stock, description) "
                        + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                        + "'A made-up product that is never saved')"));
        String[] lines = result.text().strip().split("\n");
        String errorLine = lines[lines.length - 1];
        if (!result.failed()) {
            throw new McpException("The server accepted a write");
        }
        if (!result.text().contains("SQLSTATE 25006")) {
            throw new McpException("The INSERT failed for another reason: " + errorLine);
        }
        System.out.println("INSERT rejected: " + errorLine);
    }
    // --8<-- [end:insert]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            selectCheapProducts();
            tryInsert();
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
