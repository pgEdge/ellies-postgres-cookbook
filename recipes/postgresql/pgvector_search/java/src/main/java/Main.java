/*
 * Ellie's Postgres Cookbook
 * Storing and searching vectors with pgvector, using JDBC and the
 * PostgreSQL JDBC driver (pgJDBC).
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

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

    // --8<-- [start:connect]
    /** Opens a connection with the settings from the environment. */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    // --8<-- [end:connect]

    // --8<-- [start:schema]
    /** Enables pgvector and creates a temporary table of colours. */
    static void createSchema(Connection conn) throws SQLException {
        // vector(3) fixes the number of dimensions, one for each of the
        // red, green, and blue components. The temporary table disappears
        // when the session ends, so the program can run repeatedly. An
        // HNSW index speeds up nearest-neighbour searches; vector_l2_ops
        // matches the <-> (Euclidean distance) operator used by the
        // search.
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
            stmt.execute("CREATE TEMPORARY TABLE colours ("
                    + "name text PRIMARY KEY, rgb vector(3) NOT NULL)");
            stmt.execute(
                "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
        }
    }
    // --8<-- [end:schema]

    // --8<-- [start:insert]
    /** Stores five colours, each as a vector of its RGB components. */
    static void insertColours(Connection conn) throws SQLException {
        String[][] colours = {
            {"red", "[1,0,0]"},
            {"green", "[0,1,0]"},
            {"blue", "[0,0,1]"},
            {"yellow", "[1,1,0]"},
            {"white", "[1,1,1]"},
        };

        // A vector travels as text in pgvector's [x,y,z] format, and the
        // ::vector cast converts it on the server, so the driver needs no
        // vector-specific support.
        String sql =
            "INSERT INTO colours (name, rgb) VALUES (?, ?::vector)";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            for (String[] colour : colours) {
                stmt.setString(1, colour[0]);
                stmt.setString(2, colour[1]);
                stmt.executeUpdate();
            }
        }
    }
    // --8<-- [end:insert]

    // --8<-- [start:search]
    /** Returns the names of the colours nearest to the target vector. */
    static List<String> nearestColours(
            Connection conn, String target, int count) throws SQLException {
        // <-> is the Euclidean (L2) distance operator, so ordering by it
        // puts the nearest colour first.
        String sql = "SELECT name FROM colours "
                + "ORDER BY rgb <-> ?::vector LIMIT ?";

        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, target);
            stmt.setInt(2, count);

            try (ResultSet rs = stmt.executeQuery()) {
                List<String> names = new ArrayList<>();
                while (rs.next()) {
                    names.add(rs.getString(1));
                }
                return names;
            }
        }
    }
    // --8<-- [end:search]

    // --8<-- [start:main]
    public static void main(String[] args) {
        String target = "[0.9,0.7,0.2]";

        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            createSchema(conn);
            insertColours(conn);

            System.out.println("Colours nearest to " + target + ":");
            List<String> names = nearestColours(conn, target, 3);
            for (int i = 0; i < names.size(); i++) {
                System.out.println((i + 1) + ". " + names.get(i));
            }
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
