/*
 * Ellie's Postgres Cookbook
 * Handling errors from the pgEdge RAG Server, using java.net.http and
 * Jackson.
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
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");

    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    static final String MISSING_PIPELINE = "no-such-pipeline";

    // The server rejects both requests before it calls a language model,
    // so they answer quickly.
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    // --8<-- [end:config]

    // --8<-- [start:request]
    /** Thrown when a reply is not one that the program can interpret. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }

    /**
     * Thrown when the RAG Server replies with an error. The reply has an
     * HTTP status and a JSON body of the form
     * {"error": {"code": "...", "message": "..."}}.
     */
    static class ApiException extends Exception {
        final int status;
        final String code;
        final String message;

        ApiException(int status, String code, String message) {
            super(code + ": " + message);
            this.status = status;
            this.code = code;
            this.message = message;
        }
    }

    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
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
     * Sends a query to a pipeline, and returns the decoded reply. Throws
     * ApiException when the server replies with an error.
     */
    static JsonNode sendQuery(HttpClient client, String pipeline, String query)
            throws IOException, InterruptedException, RagException, ApiException {
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(pipeline))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(
                        MAPPER.createObjectNode().put("query", query))))
                .build();
        HttpResponse<String> response =
                client.send(request, HttpResponse.BodyHandlers.ofString());

        JsonNode body;
        try {
            body = MAPPER.readTree(response.body());
        } catch (JacksonException e) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + shorten(response.body()));
        }

        if (response.statusCode() >= 400) {
            JsonNode error = body.path("error");
            if (!error.path("code").isString() || !error.path("message").isString()) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
            throw new ApiException(response.statusCode(),
                    error.path("code").stringValue(),
                    error.path("message").stringValue());
        }
        return body;
    }
    // --8<-- [end:request]

    // --8<-- [start:advise]
    /**
     * Returns advice for an error, chosen by the error code. Branch on the
     * code rather than on the message, which is meant for people and may
     * change; branch on the HTTP status only for the temporary failures
     * that have no code worth handling individually.
     */
    static String advise(ApiException err) {
        if (err.code.equals("PIPELINE_NOT_FOUND")) {
            return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
        }
        if (err.code.equals("INVALID_REQUEST")) {
            return "Fix the request; the body must be JSON with a non-empty query.";
        }
        if (err.status == 503 || err.status == 504) {
            return "The failure may be temporary, so retry the request later.";
        }
        return "This program does not handle " + err.code + ".";
    }
    // --8<-- [end:advise]

    // --8<-- [start:main]
    /**
     * Sends one query that the server must refuse with the expected error
     * code, and prints how the program handles the refusal. Any other
     * outcome is a failure.
     */
    static void demonstrate(HttpClient client, String title, String pipeline,
            String query, String expected)
            throws IOException, InterruptedException, RagException {
        System.out.println(title);
        try {
            sendQuery(client, pipeline, query);
        } catch (ApiException e) {
            System.out.println("  " + e.code + " (HTTP " + e.status + "): " + e.message);
            System.out.println("  " + advise(e));
            if (!e.code.equals(expected)) {
                throw new RagException("expected " + expected + ", got " + e.code);
            }
            return;
        }
        throw new RagException("the request unexpectedly succeeded");
    }

    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            demonstrate(client, "Asking a pipeline that does not exist",
                    MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND");
            demonstrate(client, "Asking an empty question",
                    PIPELINE, "", "INVALID_REQUEST");
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
