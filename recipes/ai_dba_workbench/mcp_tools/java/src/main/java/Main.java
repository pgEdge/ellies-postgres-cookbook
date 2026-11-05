/*
 * Ellie's Postgres Cookbook
 * Calling AI DBA Workbench MCP tools, using java.net.http and Jackson.
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
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
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

    // --8<-- [start:rpc]
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
     * Sends a JSON-RPC request to the MCP endpoint and returns the result.
     * The server answers a JSON-RPC error with HTTP status 200, so the
     * method checks the reply for an error member as well as for an HTTP
     * failure.
     */
    static JsonNode rpc(Settings cfg, String method, Object params)
            throws IOException, InterruptedException {
        String body = JSON.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method,
                "params", params));
        HttpRequest request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/mcp/v1"))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();

        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException(method + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        JsonNode reply = JSON.readTree(response.body());
        if (reply.has("error")) {
            throw new IOException(method + " failed: "
                    + reply.get("error").get("message").asString());
        }
        return reply.get("result");
    }
    // --8<-- [end:rpc]

    // --8<-- [start:initialize]
    /**
     * Introduces the client to the server and prints the server's name and
     * version. The Workbench keeps no session, so a client can skip this
     * step.
     */
    static void initialize(Settings cfg)
            throws IOException, InterruptedException {
        JsonNode result = rpc(cfg, "initialize", Map.of(
                "protocolVersion", "2024-11-05",
                "capabilities", Map.of(),
                "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
        JsonNode info = result.get("serverInfo");
        System.out.println("Server: " + info.get("name").asString() + " "
                + info.get("version").asString());
    }
    // --8<-- [end:initialize]

    // --8<-- [start:list_tools]
    /**
     * Lists the tools, checks that the two that the program calls are
     * present, and prints the arguments that each one requires.
     */
    static void listTools(Settings cfg)
            throws IOException, InterruptedException {
        // The server lists its tools in no fixed order, so look the two
        // tools up by name.
        Map<String, JsonNode> tools = new HashMap<>();
        for (JsonNode tool : rpc(cfg, "tools/list", Map.of()).get("tools")) {
            tools.put(tool.get("name").asString(), tool);
        }
        for (String name : List.of("query_database", "execute_explain")) {
            JsonNode tool = tools.get(name);
            if (tool == null) {
                throw new IOException("The server does not offer " + name);
            }
            List<String> required = JSON.convertValue(
                    tool.get("inputSchema").get("required"),
                    JSON.getTypeFactory().constructCollectionType(
                            List.class, String.class));
            System.out.println(name + " requires: "
                    + String.join(", ", required));
        }
    }
    // --8<-- [end:list_tools]

    // --8<-- [start:call_tool]
    /**
     * Calls a tool and returns the text of its reply. A tool that fails
     * returns a normal result with isError set, so the method checks that
     * flag too.
     */
    static String callTool(Settings cfg, String name,
            Map<String, Object> arguments)
            throws IOException, InterruptedException {
        JsonNode result = rpc(cfg, "tools/call",
                Map.of("name", name, "arguments", arguments));
        String text = result.get("content").get(0).get("text").asString();
        if (result.path("isError").asBoolean(false)) {
            throw new IOException(name + " failed: " + text);
        }
        return text;
    }
    // --8<-- [end:call_tool]

    // --8<-- [start:query_database]
    /**
     * Runs a harmless read-only query with query_database and prints the
     * column names and the rows. The reply is text that starts with the
     * connection and the query, and then has a "Results" line followed by
     * the rows in tab-separated form, so the method prints only what
     * follows that line.
     */
    static void queryDatabase(Settings cfg)
            throws IOException, InterruptedException {
        String text = callTool(cfg, "query_database", Map.of(
                "connection_id", cfg.connectionId(),
                "query", "SELECT 'Hello from the Workbench' AS greeting, "
                        + "6 * 7 AS answer"));
        int start = text.indexOf("\nResults");
        if (start < 0) {
            throw new IOException("The reply had no results");
        }
        // Skip the rest of the Results line, then turn the tabs into
        // commas.
        String[] lines = text.substring(start + "\nResults".length())
                .split("\n", -1);
        int number = 0;
        for (String line : Arrays.asList(lines).subList(1, lines.length)) {
            if (line.isEmpty()) {
                continue;
            }
            String label = number == 0 ? "Columns" : "Row";
            System.out.println(label + ": "
                    + String.join(", ", line.split("\t", -1)));
            number++;
        }
    }
    // --8<-- [end:query_database]

    // --8<-- [start:execute_explain]
    /** Matches the first node of the plan, after a line of equals signs. */
    static final Pattern PLAN = Pattern.compile("Execution Plan:\n=+\n(\\S+)");

    /**
     * Plans a query with execute_explain, without running it, and prints
     * the type of the first node of the plan. Setting analyze to true would
     * run the query.
     */
    static void executeExplain(Settings cfg)
            throws IOException, InterruptedException {
        String text = callTool(cfg, "execute_explain", Map.of(
                "connection_id", cfg.connectionId(),
                "query", "SELECT 1 + 1",
                "analyze", false));
        Matcher match = PLAN.matcher(text);
        if (!match.find()) {
            throw new IOException("The reply had no execution plan");
        }
        System.out.println("Plan starts with: " + match.group(1));
    }
    // --8<-- [end:execute_explain]

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
            initialize(cfg);
            listTools(cfg);
            queryDatabase(cfg);
            executeExplain(cfg);
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
