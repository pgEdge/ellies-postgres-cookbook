/*
 * Ellie's Postgres Cookbook
 * Exploring a schema through the pgEdge Postgres MCP Server, using
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
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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

    // The schema and table that scripts/start_postgres_mcp.sh creates.
    static final String SCHEMA = "cookbook_mcp";
    static final String TABLE = "products";

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

    // --8<-- [start:parse_tsv]
    /**
     * Reads the table in a tool's reply into a list of rows, each a map
     * keyed by column name. The reply starts with a line or two about the
     * database, and then has a header line and one line for each row, with
     * the values separated by tabs. The server writes a tab or a newline
     * inside a value as \t or \n, so splitting on them is safe. The header
     * is the first line that starts with "schema", the first column of
     * every table that get_schema_info returns.
     */
    static List<Map<String, String>> parseTsv(String text) throws McpException {
        // A limit of -1 keeps empty strings at the end, such as an empty
        // last column.
        String[] lines = text.split("\n", -1);
        int start = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("schema\t")) {
                start = i;
                break;
            }
        }
        if (start < 0) {
            throw new McpException("The reply had no table: " + shorten(text));
        }
        String[] header = lines[start].split("\t", -1);
        List<Map<String, String>> rows = new ArrayList<>();
        for (int i = start + 1; i < lines.length; i++) {
            if (lines[i].isEmpty()) {
                continue;
            }
            String[] values = lines[i].split("\t", -1);
            Map<String, String> row = new HashMap<>();
            for (int j = 0; j < header.length && j < values.length; j++) {
                row.put(header[j], values[j]);
            }
            rows.add(row);
        }
        return rows;
    }
    // --8<-- [end:parse_tsv]

    // --8<-- [start:list_tables]
    /**
     * Lists the tables in the schema with their comments. With compact set
     * to true, get_schema_info returns one line for each table, without its
     * columns, which suits a first look at a large database.
     */
    static void listTables() throws IOException, InterruptedException, McpException {
        String text = callTool("get_schema_info",
                Map.of("schema_name", SCHEMA, "compact", true));
        System.out.println("Tables in " + SCHEMA + ":");
        for (Map<String, String> row : parseTsv(text)) {
            String comment = row.getOrDefault("table_desc", "");
            System.out.println("- " + row.get("table") + ": "
                    + (comment.isEmpty() ? "(no comment)" : comment));
        }
    }
    // --8<-- [end:list_tables]

    // --8<-- [start:describe_table]
    /**
     * Lists the columns of one table with their types. Given a table_name,
     * get_schema_info returns one line for each column, which also carries
     * the table's details.
     */
    static void describeTable() throws IOException, InterruptedException, McpException {
        String text = callTool("get_schema_info",
                Map.of("schema_name", SCHEMA, "table_name", TABLE));
        List<Map<String, String>> rows = parseTsv(text);
        if (rows.isEmpty()) {
            throw new McpException(SCHEMA + "." + TABLE + " has no columns");
        }
        System.out.println("Columns of " + SCHEMA + "." + TABLE + ":");
        for (Map<String, String> row : rows) {
            String key = "true".equals(row.get("is_pk")) ? " (primary key)" : "";
            System.out.println("- " + row.get("column") + ": " + row.get("data_type") + key);
        }
    }
    // --8<-- [end:describe_table]

    // --8<-- [start:count_rows]
    /** Matches the line at the end of a count_rows reply, such as "Count: 4". */
    static final Pattern COUNT_LINE = Pattern.compile("^Count: (\\d+)$", Pattern.MULTILINE);

    /**
     * Counts the products in stock with count_rows. The where argument is a
     * condition without the WHERE keyword; the server rejects one that
     * contains a subquery.
     */
    static void countInStock() throws IOException, InterruptedException, McpException {
        String text = callTool("count_rows",
                Map.of("schema", SCHEMA, "table", TABLE, "where", "in_stock"));
        Matcher match = COUNT_LINE.matcher(text);
        if (!match.find()) {
            throw new McpException("The reply had no count: " + shorten(text));
        }
        System.out.println("Products in stock: " + match.group(1));
    }
    // --8<-- [end:count_rows]

    // --8<-- [start:main]
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            listTables();
            describeTable();
            countInStock();
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
