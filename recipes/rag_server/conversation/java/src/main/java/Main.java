/*
 * Ellie's Postgres Cookbook
 * Holding a conversation with the pgEdge RAG Server, using java.net.http
 * and Jackson.
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
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

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

    // The second question does not say which version of the Acme Widget
    // it means, so only the first question and its answer, which the
    // model receives as history, settle that. The search uses only the
    // current question, which is why this one still names the product.
    static final List<String> QUESTIONS = List.of(
            "How long does the Acme Widget 2.0 take to charge?",
            "And how many hours does the Acme Widget run for once it is charged?");

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

    /**
     * Sends a question and the conversation so far to the pipeline, and
     * returns the answer. The server keeps no conversation between
     * requests, so history lists the earlier messages, each with a role of
     * user or assistant, in order.
     */
    static String ask(HttpClient client, String question, ArrayNode history)
            throws IOException, InterruptedException, RagException {
        ObjectNode payload = MAPPER.createObjectNode();
        payload.put("query", question);
        payload.set("messages", history);
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        MAPPER.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response = send(client, request);

        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + errorText(response.body()));
        }

        try {
            JsonNode answer = MAPPER.readTree(response.body()).path("answer");
            if (answer.isString()) {
                return answer.stringValue();
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new RagException(
                "Unexpected response: " + shorten(response.body()));
    }
    // --8<-- [end:ask]

    // --8<-- [start:converse]
    /**
     * Asks each question in turn, printing both sides of the conversation.
     * After each answer, the question and the answer join the history that
     * the next request carries.
     */
    static void converse(HttpClient client)
            throws IOException, InterruptedException, RagException {
        ArrayNode history = MAPPER.createArrayNode();
        for (String question : QUESTIONS) {
            String answer = ask(client, question, history);
            System.out.println("You: " + question);
            System.out.println("Assistant: " + answer);
            history.addObject().put("role", "user").put("content", question);
            history.addObject().put("role", "assistant").put("content", answer);
        }
    }
    // --8<-- [end:converse]

    // --8<-- [start:main]
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            converse(client);
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
