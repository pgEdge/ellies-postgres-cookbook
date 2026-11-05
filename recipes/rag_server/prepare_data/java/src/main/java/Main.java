/*
 * Ellie's Postgres Cookbook
 * Preparing documents for the pgEdge RAG Server: embedding them with
 * Ollama and storing them in a pgvector table, using java.net.http,
 * Jackson and the PostgreSQL JDBC driver (pgJDBC).
 *
 * These examples are for pgEdge RAG Server 2.0.0.
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
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.StringJoiner;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ObjectNode;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    static final String OLLAMA_URL =
            envOr("OLLAMA_URL", "http://localhost:11434").replaceAll("/+$", "");
    static final String EMBED_MODEL = envOr("EMBED_MODEL", "nomic-embed-text");

    // This recipe uses its own table, so that it never disturbs the table
    // that a running pipeline reads.
    static final String TABLE = "cookbook_prepare_data";

    /** A row to store. */
    record Document(int id, String title, String content) {}

    // The documents to store; in a real application they come from your
    // own data. The text is fictional.
    static final List<Document> DOCUMENTS = List.of(
            new Document(1, "Charging the Acme Gadget",
                    "The Acme Gadget charges through its USB-C port. A full charge takes "
                    + "two hours, and a fully charged Acme Gadget runs for ten hours."),
            new Document(2, "Resetting the Acme Gadget",
                    "To reset the Acme Gadget to its factory settings, hold down the "
                    + "power button for eight seconds until the status light flashes red."),
            new Document(3, "Warranty for the Acme Gadget",
                    "The Acme Gadget comes with a two-year warranty that covers "
                    + "manufacturing defects but not accidental damage."));

    /**
     * Returns the JDBC URL that identifies the server and database, built
     * from the standard libpq environment variables.
     */
    static String connectionUrl() {
        return "jdbc:postgresql://"
                + envOr("PGHOST", "localhost") + ":"
                + envOr("PGPORT", "5432") + "/"
                + envOr("PGDATABASE", "postgres");
    }

    /**
     * Returns the user name and password as connection properties; the
     * password is omitted if PGPASSWORD is unset or empty.
     */
    static Properties connectionProperties() {
        Properties props = new Properties();
        props.setProperty("user", envOr("PGUSER", "postgres"));
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            props.setProperty("password", password);
        }
        return props;
    }
    // --8<-- [end:config]

    // --8<-- [start:embed]
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();

    /** Thrown when Ollama rejects a request or returns an unexpected reply. */
    static class EmbedException extends Exception {
        EmbedException(String message) {
            super(message);
        }
    }

    /**
     * Asks Ollama for the embedding of each text, in the same order.
     * pgvector stores single-precision values, so a float loses nothing
     * that the table would keep.
     */
    static List<float[]> embed(List<String> texts)
            throws IOException, InterruptedException, EmbedException {
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        ObjectNode payload = MAPPER.createObjectNode().put("model", EMBED_MODEL);
        texts.forEach(payload.putArray("input")::add);

        HttpRequest request = HttpRequest.newBuilder(URI.create(OLLAMA_URL + "/api/embed"))
                .timeout(Duration.ofSeconds(300))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response = HttpClient.newHttpClient()
                .send(request, HttpResponse.BodyHandlers.ofString());

        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            String body = response.body().strip();
            throw new EmbedException("Ollama returned HTTP " + response.statusCode()
                    + ": " + body.substring(0, Math.min(body.length(), 200)));
        }

        // path() returns a missing node, rather than null, for a field that
        // is not there, and a missing node holds no elements.
        List<float[]> embeddings = new ArrayList<>();
        for (JsonNode node : MAPPER.readTree(response.body()).path("embeddings")) {
            float[] embedding = new float[node.size()];
            for (int i = 0; i < embedding.length; i++) {
                embedding[i] = node.get(i).floatValue();
            }
            embeddings.add(embedding);
        }
        if (embeddings.size() != texts.size()) {
            throw new EmbedException("Expected " + texts.size()
                    + " embeddings, got " + embeddings.size());
        }
        return embeddings;
    }
    // --8<-- [end:embed]

    // --8<-- [start:table]
    /**
     * Creates the table, replacing any earlier copy. The vector column
     * must have the same number of dimensions as the embedding model.
     */
    static void createTable(Connection conn, int dimensions) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
            stmt.execute("DROP TABLE IF EXISTS " + TABLE);
            // The table name is a constant and the dimensions are an int,
            // so building them into the statement is safe; a statement
            // cannot take either as a parameter.
            stmt.execute("""
                    CREATE TABLE %s (
                        id        integer PRIMARY KEY,
                        title     text NOT NULL,
                        content   text NOT NULL,
                        embedding vector(%d) NOT NULL
                    )""".formatted(TABLE, dimensions));
        }
    }
    // --8<-- [end:table]

    // --8<-- [start:insert]
    /** Stores each document with its embedding, in a single batch. */
    static void insertDocuments(Connection conn, List<float[]> embeddings)
            throws SQLException {
        String sql = "INSERT INTO " + TABLE + " (id, title, content, embedding) "
                + "VALUES (?, ?, ?, ?::vector)";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            for (int i = 0; i < DOCUMENTS.size(); i++) {
                Document doc = DOCUMENTS.get(i);
                // pgvector reads a vector from text such as
                // '[0.1,0.2,0.3]', and the cast tells the server how to
                // interpret the parameter.
                StringJoiner vector = new StringJoiner(",", "[", "]");
                for (float value : embeddings.get(i)) {
                    vector.add(Float.toString(value));
                }
                stmt.setInt(1, doc.id());
                stmt.setString(2, doc.title());
                stmt.setString(3, doc.content());
                stmt.setString(4, vector.toString());
                stmt.addBatch();
            }
            stmt.executeBatch();
        }
    }
    // --8<-- [end:insert]

    // --8<-- [start:verify]
    /**
     * Returns the number of rows, and the number of dimensions of their
     * embeddings.
     */
    static long[] describeTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                     "SELECT count(*), max(vector_dims(embedding)) FROM " + TABLE)) {
            rs.next();
            return new long[] {rs.getLong(1), rs.getLong(2)};
        }
    }
    // --8<-- [end:verify]

    // --8<-- [start:cleanup]
    /**
     * Removes the table. A real application keeps it, so that the RAG
     * Server can read it.
     */
    static void dropTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS " + TABLE);
        }
    }
    // --8<-- [end:cleanup]

    // --8<-- [start:main]
    /**
     * Creates the table and inserts the documents in one transaction,
     * rolling it back if a step fails.
     */
    static void store(Connection conn, List<float[]> embeddings) throws SQLException {
        conn.setAutoCommit(false);
        try {
            createTable(conn, embeddings.get(0).length);
            insertDocuments(conn, embeddings);
            conn.commit();
        } catch (SQLException e) {
            // Attach any failure to roll back to the first error, rather
            // than letting it replace that error.
            try {
                conn.rollback();
            } catch (SQLException rollbackError) {
                e.addSuppressed(rollbackError);
            }
            throw e;
        } finally {
            conn.setAutoCommit(true);
        }
    }

    public static void main(String[] args) {
        boolean cleanupFailed = false;
        try {
            List<float[]> embeddings =
                    embed(DOCUMENTS.stream().map(Document::content).toList());
            System.out.println("Embedded " + embeddings.size()
                    + " documents with " + EMBED_MODEL);

            // try-with-resources closes the connection when the block
            // exits, whether or not an error occurred.
            try (Connection conn = DriverManager.getConnection(
                    connectionUrl(), connectionProperties())) {
                try {
                    store(conn, embeddings);
                    long[] summary = describeTable(conn);
                    System.out.println("Stored " + summary[0] + " rows with "
                            + summary[1] + "-dimension embeddings in " + TABLE);
                } finally {
                    // Remove the table whether or not a step failed. A
                    // failure here is reported on its own, so that it
                    // cannot hide the error that came first.
                    try {
                        dropTable(conn);
                    } catch (SQLException e) {
                        System.err.println("Cleanup error: " + e.getMessage());
                        cleanupFailed = true;
                    }
                }
            }
        // IOException covers failures to reach Ollama, such as a refused
        // connection or a timeout. The message of a refused connection can
        // be empty, so print the exception itself, which includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("Error: " + e);
            System.exit(1);
        // SQLException covers connection failures and errors reported by
        // the server, and JacksonException covers a reply that is not JSON.
        } catch (SQLException | EmbedException | JacksonException e) {
            System.err.println("Error: " + e.getMessage());
            System.exit(1);
        }
        if (cleanupFailed) {
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
