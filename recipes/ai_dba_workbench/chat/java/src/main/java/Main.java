/*
 * Ellie's Postgres Cookbook
 * Chatting with the LLM through the AI DBA Workbench API, using
 * java.net.http and Jackson.
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
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token) {}

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
        if (token.isEmpty()) {
            throw new IOException("WORKBENCH_TOKEN must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token);
    }
    // --8<-- [end:config]

    // --8<-- [start:request]
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
     * Sends a request to the API and returns the JSON reply. The body may
     * be null. A request that the server rejects throws an error that
     * includes the message from the server.
     */
    static JsonNode api(Settings cfg, String method, String path,
            Object body) throws IOException, InterruptedException {
        // A small model on a CPU can take a while to answer, so the
        // timeout is generous.
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                .timeout(Duration.ofSeconds(300))
                .header("Authorization", "Bearer " + cfg.token());
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }

        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new IOException(method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        return JSON.readTree(response.body());
    }
    // --8<-- [end:request]

    // --8<-- [start:providers]
    /**
     * Prints the default provider and model, which the chat endpoint uses
     * when a request names neither.
     */
    static void showProvider(Settings cfg)
            throws IOException, InterruptedException {
        JsonNode reply = api(cfg, "GET", "/llm/providers", null);
        for (JsonNode provider : reply.path("providers")) {
            if (provider.path("isDefault").asBoolean(false)) {
                System.out.println("Provider: "
                        + provider.get("name").asString() + " (model " + reply.get("defaultModel").asString()
                        + ")");
                return;
            }
        }
        throw new IOException("The Workbench has no default LLM provider");
    }
    // --8<-- [end:providers]

    // --8<-- [start:chat]
    /**
     * Sends a conversation to the model and returns the reply. The messages
     * are the conversation so far, each with a role of user or assistant
     * and some content.
     */
    static JsonNode chat(Settings cfg, List<Map<String, String>> messages)
            throws IOException, InterruptedException {
        return api(cfg, "POST", "/llm/chat", Map.of("messages", messages));
    }

    /**
     * Returns the text of a reply on a single line. A small model may
     * spread its answer over several lines, so the method joins the text
     * blocks and collapses the white space. It fails when the reply holds
     * no text.
     */
    static String replyText(JsonNode reply) throws IOException {
        List<String> blocks = new ArrayList<>();
        for (JsonNode block : reply.path("content")) {
            if ("text".equals(block.path("type").asString())) {
                blocks.add(block.path("text").asString());
            }
        }
        String text = String.join(" ", blocks).strip().replaceAll("\\s+", " ");
        if (text.isEmpty()) {
            throw new IOException("The model returned no text");
        }
        return text;
    }
    // --8<-- [end:chat]

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
            showProvider(cfg);

            // The first message starts the conversation.
            String question =
                    "Name one type of PostgreSQL index, in one sentence.";
            List<Map<String, String>> messages = new ArrayList<>();
            messages.add(Map.of("role", "user", "content", question));
            String text = replyText(chat(cfg, messages));
            System.out.println("Reply: " + text);

            // The server keeps no conversation, so the follow-up repeats
            // the earlier messages, including the model's reply, and adds
            // the new question.
            messages.add(Map.of("role", "assistant", "content", text));
            messages.add(Map.of("role", "user",
                    "content", "Summarise your answer in five words."));
            JsonNode followUp = chat(cfg, messages);
            System.out.println("Follow-up reply: " + replyText(followUp));
            System.out.println("Stop reason: "
                    + followUp.path("stop_reason").asString());
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
