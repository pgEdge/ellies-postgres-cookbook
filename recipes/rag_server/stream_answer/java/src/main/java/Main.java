/*
 * Ellie's Postgres Cookbook
 * Streaming an answer from the pgEdge RAG Server, using java.net.http and
 * Jackson.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

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

    // The server may wait for the language model before it starts to
    // answer, and a small model on a modest machine can take a while, so
    // allow plenty of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
    // --8<-- [end:config]

    // --8<-- [start:events]
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /**
     * Parses Server-Sent Events from a reader, and passes the JSON object
     * that the data of each event holds to handle, as each event arrives.
     *
     * An event is one or more "data:" lines followed by a blank line. The
     * stream may end without the final blank line, so the last event is
     * sent when the lines run out as well. readTree() throws a
     * JacksonException for data that is not valid JSON.
     */
    static void readEvents(BufferedReader reader, Consumer<JsonNode> handle)
            throws IOException {
        List<String> data = new ArrayList<>();
        String line;
        while ((line = reader.readLine()) != null) {
            if (line.isEmpty()) {
                if (!data.isEmpty()) {
                    handle.accept(MAPPER.readTree(String.join("\n", data)));
                    data.clear();
                }
            } else if (line.startsWith("data:")) {
                // A single space after the colon is not part of the data.
                String value = line.substring("data:".length());
                data.add(value.startsWith(" ") ? value.substring(1) : value);
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if (!data.isEmpty()) {
            handle.accept(MAPPER.readTree(String.join("\n", data)));
        }
    }
    // --8<-- [end:events]

    // --8<-- [start:stream]
    /** Thrown when the RAG Server rejects a request or the stream fails. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }

    /** What the stream has reported so far. */
    static class StreamState {
        int chunks = 0;
        String error = null;
        boolean done = false;
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
        String text = body.strip();
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

    /** Prints the answer as it arrives, and returns the number of chunks. */
    static int streamAnswer(HttpClient client, String question)
            throws IOException, InterruptedException, RagException {
        String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                .put("query", question)
                .put("stream", true));
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
                .build();
        // ofInputStream() returns as soon as the headers arrive, and the
        // body is read from the stream as the server sends it.
        HttpResponse<InputStream> response =
                client.send(request, HttpResponse.BodyHandlers.ofInputStream());

        StreamState state = new StreamState();
        // try-with-resources closes the stream, and with it the connection,
        // whether or not an error occurred.
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(response.body(), StandardCharsets.UTF_8))) {
            // A request the server rejects gets an ordinary error status.
            // Once streaming starts the status is always 200, so later
            // failures arrive as events instead.
            if (response.statusCode() != 200) {
                String body = new String(
                        response.body().readNBytes(4096), StandardCharsets.UTF_8);
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + errorText(body));
            }

            readEvents(reader, event -> {
                switch (event.path("type").asString()) {
                    case "chunk" -> {
                        // The last chunk has no content.
                        String content = event.path("content").asString("");
                        if (!content.isEmpty()) {
                            System.out.print(content);
                            System.out.flush();
                            state.chunks++;
                        }
                    }
                    case "error" -> {
                        String error = event.path("error").asString("");
                        state.error = error.isEmpty() ? "unknown error" : error;
                    }
                    case "done" -> state.done = true;
                    default -> {
                        // Other event types are ignored.
                    }
                }
            });
        }

        System.out.println();
        // The server sends a done event after an error event, so keep
        // reading until the stream ends before reporting the error.
        if (state.error != null) {
            throw new RagException("The stream reported an error: " + state.error);
        }
        if (!state.done) {
            throw new RagException("The stream ended before the done event");
        }
        return state.chunks;
    }
    // --8<-- [end:stream]

    // --8<-- [start:main]
    public static void main(String[] args) {
        System.out.println("Question: " + QUESTION);
        System.out.println("Answer:");
        HttpClient client = HttpClient.newHttpClient();
        try {
            int chunks = streamAnswer(client, QUESTION);
            System.out.println("Chunks received: " + chunks);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        // JacksonException is thrown for an event whose data is not valid
        // JSON.
        } catch (RagException | JacksonException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
