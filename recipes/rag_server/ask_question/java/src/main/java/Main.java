/*
 * Ellie's Postgres Cookbook
 * Asking the pgEdge RAG Server a question, using java.net.http and
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

    static final String QUESTION =
            "How long does the Acme Widget 2.0 take to charge?";

    // The server waits for the language model before it replies, and a
    // small model on a modest machine can take a while, so allow plenty
    // of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
    // --8<-- [end:config]

    // --8<-- [start:ask]
    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }

    /** The answer, and the number of tokens that the request used. */
    record Reply(String answer, long tokensUsed) {}

    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

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
     * Sends the question to the pipeline, and returns the answer with the
     * number of tokens the request used.
     */
    static Reply ask(HttpClient client, String question)
            throws IOException, InterruptedException, RagException {
        // Jackson builds the request body, which escapes the question
        // correctly.
        String payload = MAPPER.writeValueAsString(
                MAPPER.createObjectNode().put("query", question));
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
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
            JsonNode answer = body.path("answer");
            JsonNode tokensUsed = body.path("tokens_used");
            if (answer.isString() && tokensUsed.isIntegralNumber()) {
                return new Reply(answer.stringValue(), tokensUsed.longValue());
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new RagException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:ask]

    // --8<-- [start:main]
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            Reply reply = ask(client, QUESTION);
            System.out.println("Question: " + QUESTION);
            System.out.println("Answer:\n" + reply.answer());
            System.out.println("Tokens used: " + reply.tokensUsed());
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
