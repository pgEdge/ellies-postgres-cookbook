/*
 * Ellie's Postgres Cookbook
 * Listing and acknowledging alerts with the AI DBA Workbench API, using
 * java.net.http and Jackson.
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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.stream.Collectors;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /**
     * The rule that the program makes fire. The metric_staleness rule
     * alerts when a probe's data is out of date, and the alerter checks it
     * every minute.
     */
    static final String RULE_NAME = "metric_staleness";

    /**
     * The longest the whole run waits for alerts. The alerter evaluates its
     * rules once a minute and clears an alert up to 30 seconds after it
     * fires, so this allows for waiting out the alert from an earlier run,
     * one alert that clears before the program can acknowledge it, and a
     * second evaluation.
     */
    static final Duration WAIT_TIME = Duration.ofSeconds(150);

    /** How often the program polls the alerts. */
    static final Duration POLL_INTERVAL = Duration.ofMillis(500);

    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token, String connectionId) {}

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
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token, connectionId);
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
     * Sends a request to the API and returns the JSON reply. The query
     * parameters and the body may be null. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(String method, Settings cfg, String path,
            Map<String, String> params, Object body)
            throws IOException, InterruptedException {
        String url = cfg.baseUrl() + "/api/v1" + path;
        if (params != null) {
            url += "?" + params.entrySet().stream()
                    .map(p -> URLEncoder.encode(p.getKey(),
                            StandardCharsets.UTF_8) + "="
                            + URLEncoder.encode(p.getValue(),
                                    StandardCharsets.UTF_8))
                    .collect(Collectors.joining("&"));
        }
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
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
        // Some replies have no body, which reads as a missing node.
        return JSON.readTree(response.body());
    }
    // --8<-- [end:request]

    // --8<-- [start:find_rule]
    /** Returns the ID of an alert rule, given its name. */
    static long findRule(Settings cfg, String name)
            throws IOException, InterruptedException {
        for (JsonNode rule : api("GET", cfg, "/alert-rules", null, null)) {
            if (name.equals(rule.path("name").asString())) {
                return rule.get("id").asLong();
            }
        }
        throw new IOException("There is no alert rule named '" + name + "'");
    }
    // --8<-- [end:find_rule]

    // --8<-- [start:set_override]
    /**
     * Overrides the threshold of a rule for one server. A threshold of -1
     * is below any value that the staleness ratio can take, so the rule is
     * violated on the next evaluation.
     */
    static void setOverride(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        api("PUT", cfg, "/alert-overrides/server/" + cfg.connectionId()
                + "/" + ruleId, null, Map.of(
                        "operator", ">",
                        "threshold", -1,
                        "severity", "info",
                        "enabled", true));
    }
    // --8<-- [end:set_override]

    // --8<-- [start:wait_for_alert]
    /**
     * Returns the threshold alerts for the server that have the given
     * status. The request asks for the most alerts that the API returns at
     * once, so that the result does not depend on the first 100 alerts of
     * a busy Workbench.
     */
    static List<JsonNode> listAlerts(Settings cfg, String status)
            throws IOException, InterruptedException {
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("status", status);
        params.put("alert_type", "threshold");
        params.put("limit", "1000");
        List<JsonNode> alerts = new ArrayList<>();
        api("GET", cfg, "/alerts", params, null).path("alerts")
                .forEach(alerts::add);
        return alerts;
    }

    /** Returns the active alerts that the given rule raised for the server. */
    static List<JsonNode> activeAlerts(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        List<JsonNode> alerts = listAlerts(cfg, "active");
        alerts.removeIf(alert -> alert.path("rule_id").asLong() != ruleId);
        return alerts;
    }

    /**
     * Waits until the rule has no active alert. The alerter raises no new
     * alert for a rule while one is active, so an alert left by an earlier
     * run, which clears within 30 seconds, would otherwise stand in for the
     * one that this run causes.
     */
    static void waitUntilQuiet(Settings cfg, long ruleId, long deadline)
            throws IOException, InterruptedException {
        while (!activeAlerts(cfg, ruleId).isEmpty()) {
            if (System.nanoTime() - deadline >= 0) {
                throw new IOException("An earlier alert did not clear in time");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }

    /**
     * Polls until the given rule raises an alert, and returns it. The alert
     * clears itself within 30 seconds of firing, so the program polls twice
     * a second.
     */
    static JsonNode waitForAlert(Settings cfg, long ruleId, long deadline)
            throws IOException, InterruptedException {
        while (true) {
            List<JsonNode> alerts = activeAlerts(cfg, ruleId);
            if (!alerts.isEmpty()) {
                return alerts.get(0);
            }
            if (System.nanoTime() - deadline >= 0) {
                throw new IOException("No alert was raised within "
                        + WAIT_TIME.toSeconds() + " seconds");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }
    // --8<-- [end:wait_for_alert]

    // --8<-- [start:acknowledge]
    /** Acknowledges an alert, with a message that the interface shows. */
    static void acknowledgeAlert(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        api("POST", cfg, "/alerts/acknowledge", null, Map.of(
                "alert_id", alertId,
                "message", "Acknowledged by the cookbook"));
    }
    // --8<-- [end:acknowledge]

    // --8<-- [start:check]
    /**
     * Returns the status of an alert, found by its ID in the list of
     * acknowledged alerts.
     */
    static String alertStatus(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        for (JsonNode alert : listAlerts(cfg, "acknowledged")) {
            if (alert.path("id").asLong() == alertId) {
                return alert.get("status").asString();
            }
        }
        throw new IOException(
                "The alert is missing from the acknowledged alerts");
    }
    // --8<-- [end:check]

    // --8<-- [start:unacknowledge]
    /**
     * Returns an acknowledged alert to the active state. The alerter clears
     * only active alerts, so an alert that stays acknowledged also stops
     * the rule from raising a new one.
     */
    static void unacknowledgeAlert(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        api("DELETE", cfg, "/alerts/acknowledge",
                Map.of("alert_id", Long.toString(alertId)), null);
    }
    // --8<-- [end:unacknowledge]

    // --8<-- [start:remove_override]
    /**
     * Removes the override, so that the rule reverts to its default
     * threshold.
     */
    static void removeOverride(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        api("DELETE", cfg, "/alert-overrides/server/" + cfg.connectionId()
                + "/" + ruleId, null, null);
    }
    // --8<-- [end:remove_override]

    // --8<-- [start:main]
    /** Reports whether a list of alerts includes the one with an ID. */
    static boolean contains(List<JsonNode> alerts, long alertId) {
        return alerts.stream()
                .anyMatch(a -> a.path("id").asLong() == alertId);
    }

    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }

    public static void main(String[] args) {
        Settings cfg = null;
        Long overrideRule = null;
        Long acknowledgedAlert = null;
        int status = 0;
        try {
            cfg = settings();
            long deadline = System.nanoTime() + WAIT_TIME.toNanos();

            long ruleId = findRule(cfg, RULE_NAME);
            System.out.println("Found the rule '" + RULE_NAME + "'");

            // An alert from an earlier run may still be active.
            waitUntilQuiet(cfg, ruleId, deadline);

            // Record the override first and remove it at the end, so that
            // a failed run does not leave the server raising alerts.
            overrideRule = ruleId;
            setOverride(cfg, ruleId);
            System.out.println("Set an override that makes the rule fire");

            System.out.println("Waiting for the alerter to raise an alert");
            JsonNode alert;
            while (true) {
                alert = waitForAlert(cfg, ruleId, deadline);
                long alertId = alert.get("id").asLong();

                // Record the alert before acknowledging it, so that the
                // clean-up returns it to the active state even if the
                // request times out after the server has acted on it.
                acknowledgedAlert = alertId;
                try {
                    acknowledgeAlert(cfg, alertId);
                    break;
                } catch (IOException e) {
                    // The alerter may have cleared the alert since the
                    // poll. The override is still in place, so the rule
                    // fires again at the next evaluation; any other
                    // failure is real.
                    if (contains(activeAlerts(cfg, ruleId), alertId)) {
                        // The server did not acknowledge it, so there is
                        // nothing to undo.
                        acknowledgedAlert = null;
                        throw e;
                    }
                    // If the server acted on a request that timed out, the
                    // alert is acknowledged and must go back to active.
                    // When that fails, the error propagates and the
                    // clean-up tries again, because acknowledgedAlert is
                    // still set.
                    if (contains(listAlerts(cfg, "acknowledged"), alertId)) {
                        unacknowledgeAlert(cfg, alertId);
                    }
                    acknowledgedAlert = null;
                    System.err.println(
                            "The alert cleared first; waiting for the next one");
                }
            }
            long alertId = alert.get("id").asLong();
            System.out.println("An alert is active (severity: "
                    + alert.get("severity").asString() + ")");
            System.out.println("Acknowledged the alert");

            System.out.println("The alert is now "
                    + alertStatus(cfg, alertId));

            unacknowledgeAlert(cfg, alertId);
            acknowledgedAlert = null;
            System.out.println("Returned the alert to the active state");

            removeOverride(cfg, ruleId);
            overrideRule = null;
            System.out.println("Removed the override");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }

        // Undo the changes whether or not a step failed, so that the server
        // does not keep raising alerts or hold an acknowledged one.
        if (acknowledgedAlert != null) {
            try {
                unacknowledgeAlert(cfg, acknowledgedAlert);
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: could not undo a change: "
                        + describe(e));
                status = 1;
            }
        }
        if (overrideRule != null) {
            try {
                removeOverride(cfg, overrideRule);
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: could not undo a change: "
                        + describe(e));
                status = 1;
            }
        }
        System.exit(status);
    }
    // --8<-- [end:main]
}
