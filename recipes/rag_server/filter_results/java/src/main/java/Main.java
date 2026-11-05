/*
 * Ellie's Postgres Cookbook
 * Filtering the documents that the pgEdge RAG Server retrieves, using
 * java.net.http and Jackson.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ArrayNode;
import tools.jackson.databind.node.ObjectNode;
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
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");

    static final String QUESTION =
            "How long does the Acme Widget take to charge?";

    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline
    // which documents to use.
    static final String PRODUCT = "Acme Widget";
    static final List<String> VERSIONS = List.of("1.0", "2.0");

    // The server waits for the language model before it replies, and a
    // small model on a modest machine can take a while, so allow plenty
    // of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
    // --8<-- [end:config]

    // --8<-- [start:filter]
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /**
     * Returns the filter for a product and a version. The conditions are
     * joined with AND, which is the default, and each one compares a column
     * of the pipeline's table with a value. The server passes the values to
     * PostgreSQL as parameters, so they need no escaping.
     */
    static ObjectNode buildFilter(String product, String version) {
        ObjectNode filter = MAPPER.createObjectNode().put("logic", "AND");
        ArrayNode conditions = filter.putArray("conditions");
        conditions.addObject()
                .put("column", "product").put("operator", "=").put("value", product);
        conditions.addObject()
                .put("column", "version").put("operator", "=").put("value", version);
        return filter;
    }
    // --8<-- [end:filter]

    // --8<-- [start:ask]
    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }

    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    /**
     * Describes an error response, which carries a JSON body of the form
     * {"error": {"code": "...", "message": "..."}}.
     */
    static String errorText(String body) {
        try {
            JsonNode error = MAPPER.readTree(body).path("error");
            if (error.path("code").isString()) {
                return error.path("code").stringValue() + ": "
                        + error.path("message").asString();
            }
        } catch (JacksonException e) {
            // The body is not JSON, so show it as it is.
        }
        return shorten(body.strip());
    }

    /**
     * Returns the URL of a pipeline. URLEncoder escapes any character that
     * is not safe in a URL, but it writes a space as + for an HTML form,
     * so the + becomes %20 for use in a URL path.
     */
    static URI pipelineUri(String pipeline) {
        String name = URLEncoder.encode(pipeline, StandardCharsets.UTF_8)
                .replace("+", "%20");
        return URI.create(BASE_URL + "/v1/pipelines/" + name);
    }

    /**
     * Sends the question and the filter to the pipeline, and asks for the
     * documents that the answer came from. Returns the decoded reply.
     */
    static JsonNode ask(HttpClient client, String question, ObjectNode filter)
            throws IOException, InterruptedException, RagException {
        ObjectNode payload = MAPPER.createObjectNode();
        payload.put("query", question);
        payload.set("filter", filter);
        payload.put("include_sources", true);
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        MAPPER.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response =
                client.send(request, HttpResponse.BodyHandlers.ofString());

        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + errorText(response.body()));
        }

        try {
            JsonNode body = MAPPER.readTree(response.body());
            if (body.path("answer").isString()) {
                return body;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new RagException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:ask]

    // --8<-- [start:show]
    /** Prints the answer in a reply, and then the IDs of its sources. */
    static void show(JsonNode body) {
        // path() gives a missing node, which holds no elements, when the
        // reply has no sources.
        List<String> ids = new ArrayList<>();
        for (JsonNode source : body.path("sources")) {
            ids.add(source.has("id") ? source.get("id").asString() : "(no id)");
        }
        System.out.println("Answer:\n" + body.path("answer").stringValue());
        System.out.println("Sources: " + String.join(", ", ids));
    }
    // --8<-- [end:show]

    // --8<-- [start:main]
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            System.out.println("Question: " + QUESTION);
            for (String version : VERSIONS) {
                JsonNode body = ask(client, QUESTION, buildFilter(PRODUCT, version));
                System.out.println();
                System.out.println(
                        "Filter: product = " + PRODUCT + ", version = " + version);
                show(body);
            }
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        } catch (RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
