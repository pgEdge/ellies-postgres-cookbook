/*
 * Ellie's Postgres Cookbook
 * Creating a branch of a pgEdge Starfleet database for a test run, and
 * connecting to it, using java.net.http, Jackson, and pgJDBC.
 *
 * The program creates a database of its own to branch. The Starfleet
 * service bills for every database and every branch from the moment that it
 * becomes connectable, so the program deletes the branch and then the
 * database on every path: after a success, after a failure, and after
 * Ctrl-C.
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
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.postgresql.util.PSQLException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /**
     * How long to wait for a database to become available, or to disappear
     * after a delete, and how often to check.
     */
    static final int TIMEOUT_SECONDS = 900;
    static final int POLL_SECONDS = 10;

    /** How many times to look for a database whose create reply was lost. */
    static final int LOOKUP_ATTEMPTS = 3;

    /** How many times to try connecting to the database before giving up. */
    static final int CONNECT_ATTEMPTS = 6;

    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String clientId, String clientSecret) {}

    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    /**
     * Reads the API settings from the environment. The client ID and secret
     * have no defaults, so a missing value becomes null, and the token
     * request reports it.
     */
    static Settings settings() {
        return new Settings(
                envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                        .replaceAll("/+$", ""),
                envOr("STARFLEET_CLIENT_ID", null),
                envOr("STARFLEET_CLIENT_SECRET", null));
    }

    /**
     * Returns a deadline the given number of seconds from now, on a clock
     * that only moves forwards.
     */
    static long deadline(int seconds) {
        return System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
    }

    /** Reports whether a deadline is still in the future. */
    static boolean before(long deadline) {
        return System.nanoTime() - deadline < 0;
    }

    /**
     * Guards the state that the clean-up uses, which the main thread and
     * the shutdown hook share (see main).
     */
    static final Object LOCK = new Object();

    /** Set by the shutdown hook when SIGINT or SIGTERM arrives. */
    static volatile boolean interrupted;

    /**
     * Throws InterruptedException once a signal has arrived, so that the
     * main thread stops making requests. A thread that holds the lock is
     * either creating the database or cleaning up, and both of those must
     * run to the end.
     */
    static void checkInterrupted() throws InterruptedException {
        if (interrupted && !Thread.holdsLock(LOCK)) {
            throw new InterruptedException("interrupted");
        }
    }

    /** Waits for the given number of seconds, watching for a signal. */
    static void pause(int seconds) throws InterruptedException {
        long end = deadline(seconds);
        while (before(end)) {
            checkInterrupted();
            Thread.sleep(200);
        }
    }
    // --8<-- [end:config]

    // --8<-- [start:token]
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();

    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();

    /** An error reply from the API, with its HTTP status. */
    static class ApiException extends IOException {
        final int status;

        ApiException(int status, String message) {
            super(message);
            this.status = status;
        }
    }

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

    /**
     * Sends a request with a JSON body, if there is one, and returns the
     * decoded JSON reply, or null if the reply has no body. A 4xx or 5xx
     * reply throws an ApiException.
     */
    static JsonNode request(String method, String url, String path,
            String token, Object body) throws IOException, InterruptedException {
        checkInterrupted();
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30));
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }

        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new ApiException(response.statusCode(), method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        String text = response.body();
        return text.isEmpty() ? null : JSON.readTree(text);
    }

    /**
     * Returns a field of a JSON object as text, and throws if the field is
     * missing.
     */
    static String field(JsonNode node, String name) {
        JsonNode value = (node == null) ? null : node.get(name);
        if (value == null || value.isNull()) {
            throw new IllegalStateException("the reply has no " + name);
        }
        return value.asString();
    }

    /**
     * Exchanges the client ID and secret for an access token, which the
     * Managed API accepts as a bearer token until it expires.
     */
    static String getToken(Settings cfg) throws IOException, InterruptedException {
        if (cfg.clientId() == null || cfg.clientSecret() == null) {
            throw new IllegalStateException(
                    "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
        String path = "/account/v1/oauth/token";
        JsonNode token = request("POST", cfg.baseUrl() + path, path, null, Map.of(
                "grant_type", "client_credentials",
                "client_id", cfg.clientId(),
                "client_secret", cfg.clientSecret()));
        return field(token, "access_token");
    }
    // --8<-- [end:token]

    // --8<-- [start:api]
    /**
     * Sends an authenticated request to the Managed API and returns the
     * decoded JSON reply, or null if the reply has no body.
     */
    static JsonNode api(Settings cfg, String token, String method, String path,
            Object body) throws IOException, InterruptedException {
        return request(method, cfg.baseUrl() + "/managed/v1" + path, path,
                token, body);
    }
    // --8<-- [end:api]

    // --8<-- [start:placement]
    /** The region and size of a new database. */
    record Placement(String region, String size) {}

    /**
     * Returns the region and size for the new database. The API lists sizes
     * smallest first, so the first one is the cheapest. The API does not
     * price regions, so the example takes the first one.
     */
    static Placement choosePlacement(Settings cfg, String token)
            throws IOException, InterruptedException {
        JsonNode regions = api(cfg, token, "GET", "/regions", null);
        JsonNode sizes = api(cfg, token, "GET", "/sizes", null);
        if (regions == null || sizes == null || regions.size() == 0
                || sizes.size() == 0) {
            throw new IllegalStateException("the API offers no region or size");
        }
        return new Placement(field(regions.get(0), "region"),
                field(sizes.get(0), "name"));
    }
    // --8<-- [end:placement]

    // --8<-- [start:create]
    /** Returns the address that the API sees requests come from. */
    static String clientIp(Settings cfg, String token)
            throws IOException, InterruptedException {
        // A new database is closed to everyone until an allowlist rule
        // admits an address. The API reports the address it sees this
        // request come from, which is the one to admit; a bare address
        // means a single host.
        return field(api(cfg, token, "GET", "/client-ip", null), "ip_address");
    }

    /**
     * Creates a database that only this machine can reach, and returns the
     * API's description of it, which includes its ID.
     */
    static JsonNode createDatabase(Settings cfg, String token, String name,
            String displayName, Placement placement, String ip)
            throws IOException, InterruptedException {
        return api(cfg, token, "POST", "/databases", Map.of(
                // The name becomes the Postgres database name, so it holds
                // only letters and digits, and the readable cookbook- prefix
                // goes in the display name. The program also uses the name
                // to find the database again if the reply to this request
                // is lost.
                "name", name,
                "display_name", displayName,
                "region", placement.region(),
                "size", placement.size(),
                "ip_allowlist", Map.of("rules", List.of(
                        Map.of("cidr", ip, "label", "cookbook")))));
    }
    // --8<-- [end:create]

    // --8<-- [start:wait]
    /**
     * The API does not document its status values; the example treats
     * these two as failures, which end the wait at once instead of leaving
     * it to run until the time limit.
     */
    static final Set<String> FAILED_STATUSES = Set.of("degraded", "failed");

    /** Polls the database until its status is available. */
    static void waitUntilAvailable(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        String last = null;
        while (before(deadline)) {
            String status = field(
                    api(cfg, token, "GET", "/databases/" + databaseId, null),
                    "status");
            if (!status.equals(last)) {
                System.out.println("Database status: " + status);
                last = status;
            }
            if (status.equals("available")) {
                return;
            }
            if (FAILED_STATUSES.contains(status)) {
                throw new IllegalStateException(
                        "the database has the status " + status);
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the database was not available after "
                + TIMEOUT_SECONDS + " seconds");
    }
    // --8<-- [end:wait]

    // --8<-- [start:branch]
    /**
     * Creates a copy-on-write branch of the database, and returns the API's
     * description of it, which includes its ID.
     */
    static JsonNode createBranch(Settings cfg, String token, String databaseId,
            String displayName) throws IOException, InterruptedException {
        // The API assigns the name of a branch, so the program gives the
        // branch a display name and uses that to find it again if the reply
        // to this request is lost. The request sets no allowlist, so the
        // branch copies the rules of the database, which admit this
        // machine. The branch also copies the size, the region, and the
        // Postgres version.
        return api(cfg, token, "POST", "/databases/" + databaseId + "/branches",
                Map.of("display_name", displayName));
    }

    /** Polls the branch until its status is available. */
    static void waitUntilBranchAvailable(Settings cfg, String token,
            String branchPath) throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        String last = null;
        while (before(deadline)) {
            String status = field(api(cfg, token, "GET", branchPath, null),
                    "status");
            if (!status.equals(last)) {
                System.out.println("Branch status: " + status);
                last = status;
            }
            if (status.equals("available")) {
                return;
            }
            if (FAILED_STATUSES.contains(status)) {
                throw new IllegalStateException(
                        "the branch has the status " + status);
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the branch was not available after "
                + TIMEOUT_SECONDS + " seconds");
    }
    // --8<-- [end:branch]

    // --8<-- [start:connection]
    /** The address and settings of a database, for pgJDBC. */
    record ConnectionSettings(String url, Properties properties) {}

    /** Returns a field of a JSON object as text, or null if it is missing. */
    static String optional(JsonNode node, String name) {
        JsonNode value = node.get(name);
        return (value == null || value.isNull() || value.asString().isEmpty())
                ? null : value.asString();
    }

    /**
     * Reads the connection details of an available branch, and returns them
     * as a JDBC URL and properties.
     */
    static ConnectionSettings connectionSettings(Settings cfg, String token,
            String branchPath) throws IOException, InterruptedException {
        // The connection details, including the password of the branch's own
        // application user, come with the description of the branch. They
        // are present only while the branch is available. The API does not
        // require the host, so fall back to the external IP address if it
        // is missing.
        JsonNode connection = api(cfg, token, "GET", branchPath, null)
                .path("connection");
        String host = Objects.requireNonNullElse(optional(connection, "host"),
                Objects.requireNonNullElse(
                        optional(connection, "external_ip_address"), ""));
        String port = Objects.requireNonNullElse(optional(connection, "port"), "");
        String database = Objects.requireNonNullElse(
                optional(connection, "database"), "");
        String user = optional(connection, "username");
        String password = optional(connection, "password");
        if (host.isEmpty() || port.isEmpty() || database.isEmpty()
                || user == null || password == null) {
            throw new IllegalStateException(
                    "the database description has incomplete connection details");
        }

        // The password goes in the properties rather than the URL, so that
        // it cannot appear in an error message that quotes the URL.
        Properties properties = new Properties();
        properties.setProperty("user", user);
        properties.setProperty("password", password);
        // Encrypt the connection. The certificate of a Starfleet database is
        // not signed by a public authority, so the example does not verify
        // it; pgJDBC checks no certificate in require mode.
        properties.setProperty("sslmode", "require");
        properties.setProperty("connectTimeout", "15");
        return new ConnectionSettings(
                "jdbc:postgresql://" + host + ":" + port + "/" + database,
                properties);
    }
    // --8<-- [end:connection]

    // --8<-- [start:query]
    /** Connects to the database and returns the server's version string. */
    static String serverVersion(ConnectionSettings connection)
            throws SQLException, InterruptedException {
        // A database can refuse connections for a short while after the API
        // reports it as available, so try a few times before giving up. An
        // error that carries a message from the server, such as a failed
        // login, will not change on a second attempt; pgJDBC gives one only
        // for errors that came from the server itself.
        for (int attempt = 0; ; attempt++) {
            checkInterrupted();
            // The try-with-resources block closes the connection when it
            // exits, whether or not an error occurred.
            try (Connection conn = DriverManager.getConnection(
                            connection.url(), connection.properties());
                    Statement statement = conn.createStatement();
                    ResultSet rows = statement.executeQuery("SELECT version()")) {
                rows.next();
                return rows.getString(1);
            } catch (SQLException e) {
                boolean fromServer = e instanceof PSQLException psql
                        && psql.getServerErrorMessage() != null;
                if (fromServer || attempt == CONNECT_ATTEMPTS - 1) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }
    }
    // --8<-- [end:query]

    // --8<-- [start:delete]
    /**
     * Reports whether a failed request is worth repeating: no reply arrived,
     * the service is overloaded or failing, or it answered 409, which the
     * API does whilst a database is still being created. Any IOException
     * other than an ApiException means that no reply arrived, such as a
     * refused connection or a timeout.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ApiException api) {
            return api.status == 409 || api.status == 429 || api.status >= 500;
        }
        return e instanceof IOException;
    }

    /**
     * Reports whether an error is a 404 reply, which means that the database
     * does not exist.
     */
    static boolean isGone(Exception e) {
        return e instanceof ApiException api && api.status == 404;
    }

    /**
     * Returns the ID of the database with the given name, or null. The
     * program uses this when it cannot tell whether a create request worked.
     * It repeats the request, as the delete does, because the fault that
     * lost the reply to the create request may still be there. The request
     * asks for the newest databases first, but the API does not say which
     * property it sorts on.
     */
    static String findDatabase(Settings cfg, String token, String name)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        JsonNode databases;
        while (true) {
            try {
                databases = api(cfg, token, "GET",
                        "/databases?limit=100&descending=true", null);
                break;
            } catch (IOException e) {
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }
        if (databases != null) {
            for (JsonNode database : databases) {
                if (name.equals(database.path("name").asString())) {
                    return field(database, "id");
                }
            }
        }
        return null;
    }

    /**
     * Looks for the database a few times, because the service may not have
     * recorded a request whose reply was lost until a little later. Returns
     * null if the database never appears.
     */
    static String findCreatedDatabase(Settings cfg, String token, String name)
            throws IOException, InterruptedException {
        for (int attempt = 0; attempt < LOOKUP_ATTEMPTS; attempt++) {
            String databaseId = findDatabase(cfg, token, name);
            if (databaseId != null) {
                return databaseId;
            }
            if (attempt < LOOKUP_ATTEMPTS - 1) {
                pause(POLL_SECONDS);
            }
        }
        return null;
    }

    /**
     * Reports whether a failed create request might still have created the
     * database: no reply arrived, the reply could not be read, or the
     * service failed with a 5xx status. A 4xx reply is a definite refusal.
     */
    static boolean outcomeUnknown(Exception e) {
        if (e instanceof ApiException api) {
            return api.status >= 500;
        }
        return true;
    }

    /**
     * Returns the branches of the database that have not been deleted,
     * newest first. The request repeats, as the deletes do, and a 404 means
     * that the database has gone, and so have its branches.
     */
    static List<JsonNode> listBranches(Settings cfg, String token,
            String databaseId) throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        while (true) {
            try {
                JsonNode branches = api(cfg, token, "GET", "/databases/"
                        + databaseId + "/branches?limit=100&descending=true", null);
                List<JsonNode> list = new ArrayList<>();
                if (branches != null) {
                    branches.forEach(list::add);
                }
                return list;
            } catch (IOException e) {
                if (isGone(e)) {
                    return List.of();
                }
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }
    }

    /**
     * Looks for the branch with the given display name a few times, because
     * the service may not have recorded a request whose reply was lost until
     * a little later. Returns null if the branch never appears.
     */
    static String findCreatedBranch(Settings cfg, String token,
            String databaseId, String displayName)
            throws IOException, InterruptedException {
        for (int attempt = 0; attempt < LOOKUP_ATTEMPTS; attempt++) {
            for (JsonNode branch : listBranches(cfg, token, databaseId)) {
                if (displayName.equals(branch.path("display_name").asString())) {
                    return field(branch, "id");
                }
            }
            if (attempt < LOOKUP_ATTEMPTS - 1) {
                pause(POLL_SECONDS);
            }
        }
        return null;
    }

    /** Deletes the branch and waits until the API no longer lists it. */
    static void deleteBranch(Settings cfg, String token, String databaseId,
            String branchId) throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        while (true) {
            try {
                api(cfg, token, "DELETE", "/databases/" + databaseId
                        + "/branches/" + branchId, null);
                break;
            } catch (IOException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }

        // The API takes a branch out of the list as soon as it accepts the
        // delete, even though the teardown carries on afterwards.
        while (before(deadline)) {
            boolean listed = false;
            for (JsonNode branch : listBranches(cfg, token, databaseId)) {
                if (branchId.equals(field(branch, "id"))) {
                    listed = true;
                }
            }
            if (!listed) {
                return;
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the branch was still listed after "
                + TIMEOUT_SECONDS + " seconds");
    }

    /** Deletes the database and waits until the API no longer lists it. */
    static void deleteDatabase(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        while (true) {
            try {
                // The API refuses to delete a database that has branches,
                // with a 409 reply, unless force=true, which deletes every
                // branch first. The program has deleted its branch by now,
                // so this is a safety net for a branch that the program
                // could not find.
                api(cfg, token, "DELETE", "/databases/" + databaseId
                        + "?force=true", null);
                break;
            } catch (IOException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }

        // The delete starts the teardown; a 404 shows that it has finished.
        while (before(deadline)) {
            try {
                api(cfg, token, "GET", "/databases/" + databaseId, null);
            } catch (IOException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e)) {
                    throw e;
                }
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the database was still present after "
                + TIMEOUT_SECONDS + " seconds");
    }
    // --8<-- [end:delete]

    // --8<-- [start:main]
    // What the clean-up needs to know, guarded by LOCK.
    static Settings cfg;
    static String token;
    static String name;
    static String databaseId;
    static boolean lookup;
    static String branchId;
    static String branchName;
    static boolean branchLookup;
    /** The exit status, once the clean-up has run. */
    static Integer result;
    /** Set once the clean-up has started. */
    static volatile boolean cleaning;
    /** Set once the main thread has finished, clean-up included. */
    static volatile boolean exiting;

    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }

    /**
     * Deletes the database, if the program created one, and returns the
     * exit status. The main thread and the shutdown hook both call this,
     * and whichever comes first does the work; the other waits for it and
     * gets the same status.
     */
    static int cleanUp(int status) {
        synchronized (LOCK) {
            if (result != null) {
                return result;
            }
            cleaning = true;
            if (token != null && name != null) {
                try {
                    if (databaseId == null && lookup) {
                        databaseId = findCreatedDatabase(cfg, token, name);
                        if (databaseId == null) {
                            System.err.println("Error: the database " + name
                                    + " was not found; check your account for"
                                    + " it by hand");
                            status = 1;
                        }
                    }
                    if (databaseId != null) {
                        // Delete the branch before the database. A failure
                        // here must not stop the database delete, which uses
                        // force=true as a safety net.
                        try {
                            if (branchId == null && branchLookup) {
                                branchId = findCreatedBranch(cfg, token,
                                        databaseId, branchName);
                                if (branchId == null) {
                                    System.err.println("Error: the branch "
                                            + branchName + " was not found;"
                                            + " check your account for it by"
                                            + " hand");
                                    status = 1;
                                }
                            }
                            if (branchId != null) {
                                deleteBranch(cfg, token, databaseId, branchId);
                                System.out.println("Deleted branch");
                            }
                        } catch (IOException | JacksonException
                                | IllegalStateException e) {
                            System.err.println("Error: " + describe(e));
                            System.err.println("The forced delete of the"
                                    + " database that follows also deletes"
                                    + " the branch");
                            status = 1;
                        }
                        deleteDatabase(cfg, token, databaseId);
                        System.out.println("Deleted database");
                    }
                } catch (IOException | InterruptedException | JacksonException
                        | IllegalStateException e) {
                    System.err.println("Error: " + describe(e));
                    System.err.println("Delete the database "
                            + (databaseId != null ? databaseId : name)
                            + " and any branches by hand, because it may"
                            + " still be billing");
                    status = 1;
                }
            }
            result = status;
            return status;
        }
    }

    public static void main(String[] args) {
        // Java cannot catch a signal with its supported API, but SIGINT and
        // SIGTERM start an orderly shutdown that runs this hook. The hook
        // stops the main thread's requests, deletes the database (or waits
        // for the main thread to finish doing so), and ends the program
        // with the status of the clean-up. A normal exit runs the hook too,
        // after the main thread has cleaned up.
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (!exiting) {
                interrupted = true;
                if (!cleaning) {
                    System.err.println("Interrupted");
                }
            }
            int status = cleanUp(130);
            System.out.flush();
            Runtime.getRuntime().halt(status);
        }));

        // The status stays 1 unless every step succeeds, so that an
        // unexpected error, which the catch does not handle, still ends
        // the program with a failure.
        int status = 1;
        try {
            cfg = settings();
            String bearer = getToken(cfg);
            synchronized (LOCK) {
                token = bearer;
            }

            Placement placement = choosePlacement(cfg, bearer);
            System.out.println("Region: " + placement.region());
            System.out.println("Size: " + placement.size());

            // Choose the name before the request, so that the program can
            // find the database even if the reply to the request never
            // arrives.
            byte[] random = new byte[3];
            new SecureRandom().nextBytes(random);
            String suffix = HexFormat.of().formatHex(random);
            String displayName = "cookbook-" + suffix;
            String ip = clientIp(cfg, bearer);
            JsonNode database;
            // Hold the lock until the ID is recorded, so that a signal
            // during the create call cannot leave the database behind.
            synchronized (LOCK) {
                name = "cookbook" + suffix;
                // Look the database up by name afterwards only if the
                // outcome of the request is unknown, so that a refusal
                // cannot lead the clean-up to delete another database that
                // has the same name.
                lookup = true;
                try {
                    database = createDatabase(cfg, bearer, name, displayName,
                            placement, ip);
                } catch (IOException | JacksonException e) {
                    lookup = outcomeUnknown(e);
                    throw e;
                }
                databaseId = field(database, "id");
            }
            System.out.println("Created database " + field(database, "display_name"));

            waitUntilAvailable(cfg, bearer, databaseId);
            System.out.println("Database is available");

            // The program names the branch before the request, as it does
            // the database, and looks it up afterwards only if the outcome
            // is unknown. The lock covers the request for the same reason.
            JsonNode branch;
            synchronized (LOCK) {
                branchName = "cookbook-" + suffix + "-branch";
                branchLookup = true;
                try {
                    branch = createBranch(cfg, bearer, databaseId, branchName);
                } catch (IOException | JacksonException e) {
                    branchLookup = outcomeUnknown(e);
                    throw e;
                }
                branchId = field(branch, "id");
            }
            System.out.println("Created branch " + field(branch, "display_name"));

            String branchPath = "/databases/" + databaseId + "/branches/" + branchId;
            waitUntilBranchAvailable(cfg, bearer, branchPath);
            System.out.println("Branch is available");

            ConnectionSettings connection = connectionSettings(cfg, bearer,
                    branchPath);
            System.out.println("Branch server version: "
                    + serverVersion(connection));
            status = 0;
        // IOException covers failures to connect and error replies from the
        // API; SQLException covers every error from pgJDBC;
        // InterruptedException means that a signal arrived, which the
        // shutdown hook reports; Jackson throws JacksonException for a
        // reply that is not JSON; and IllegalStateException covers replies
        // that the program cannot use.
        } catch (IOException | SQLException | InterruptedException
                | JacksonException | IllegalStateException e) {
            if (!interrupted) {
                System.err.println("Error: " + describe(e));
            }
        } finally {
            // Delete the database whether the example succeeded, failed, or
            // was interrupted, because the service bills for it until then.
            // The finally block also runs for an error that the catch does
            // not handle.
            status = cleanUp(interrupted ? 130 : status);
        }
        exiting = true;
        System.exit(status);
    }
    // --8<-- [end:main]
}
