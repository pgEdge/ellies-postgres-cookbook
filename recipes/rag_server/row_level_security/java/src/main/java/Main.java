/*
 * Ellie's Postgres Cookbook
 * Answering each caller from only their own documents with the pgEdge RAG
 * Server and row-level security, using java.net.http and Jackson.
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
import java.util.ArrayList;
import java.util.List;
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
            envOr("RAG_SERVER_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook_private");

    static final String QUESTION = "What is the status of my warranty claim?";

    // The callers to ask for. The fictional documents in the pipeline's
    // table belong to these two people.
    static final List<String> CALLERS =
            List.of("jane.doe@example.com", "john.smith@example.com");

    // The header in which the server expects a trusted proxy to put the
    // claims of the caller. This is the server's default; the
    // identity.claims_header setting changes it.
    static final String CLAIMS_HEADER = "X-Forwarded-Claims";

    // The server waits for the language model before it replies, and a
    // small model on a modest machine can take a while, so allow plenty
    // of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
    // --8<-- [end:config]

    // --8<-- [start:ask]
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

        ApiException(int status, String code, String message) {
            super(code + ": " + message);
            this.status = status;
            this.code = code;
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
     * Sends the question to the pipeline on behalf of a caller, and asks
     * for the documents that the answer came from. Returns the decoded
     * reply. A subject of null sends no identity at all.
     */
    static JsonNode ask(HttpClient client, String subject)
            throws IOException, InterruptedException, RagException, ApiException {
        String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                .put("query", QUESTION)
                .put("include_sources", true));
        HttpRequest.Builder builder = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload));
        // The claims are a JSON object, which Jackson builds, so that the
        // subject needs no escaping.
        if (subject != null) {
            builder.header(CLAIMS_HEADER, MAPPER.writeValueAsString(
                    MAPPER.createObjectNode().put("sub", subject)));
        }
        HttpResponse<String> response = send(client, builder.build());

        JsonNode body = null;
        try {
            body = MAPPER.readTree(response.body());
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }

        if (response.statusCode() >= 400) {
            JsonNode error = body == null ? null : body.path("error");
            if (error == null || !error.path("code").isString()
                    || !error.path("message").isString()) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
            throw new ApiException(response.statusCode(),
                    error.path("code").stringValue(),
                    error.path("message").stringValue());
        }

        if (body == null || !body.path("answer").isString()) {
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
        }
        return body;
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
    /**
     * Asks the question without an identity. The server must refuse with
     * IDENTITY_REQUIRED, because it never falls back to the pipeline's own
     * database role; any other outcome is a failure.
     */
    static void askAnonymously(HttpClient client)
            throws IOException, InterruptedException, RagException {
        System.out.println();
        System.out.println("Caller: (no identity)");
        try {
            ask(client, null);
        } catch (ApiException e) {
            System.out.println(e.code + " (HTTP " + e.status + ")");
            if (!e.code.equals("IDENTITY_REQUIRED")) {
                throw new RagException(
                        "expected IDENTITY_REQUIRED, got " + e.getMessage());
            }
            return;
        }
        throw new RagException("the server answered without an identity; "
                + "is identity.enabled set?");
    }

    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            System.out.println("Question: " + QUESTION);
            for (String caller : CALLERS) {
                JsonNode body = ask(client, caller);
                System.out.println();
                System.out.println("Caller: " + caller);
                show(body);
            }
            askAnonymously(client);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        } catch (ApiException | RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
