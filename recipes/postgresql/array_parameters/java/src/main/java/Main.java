/*
 * Ellie's Postgres Cookbook
 * Passing a list of values as a single array parameter, using JDBC and
 * the PostgreSQL JDBC driver (pgJDBC).
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.sql.Array;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
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

    // --8<-- [start:query]
    /** Returns the names from the list that exist as data types. */
    static List<String> findTypes(Connection conn, String[] names)
            throws SQLException {
        // The whole list travels as one array parameter, so the SQL text
        // is the same however many values the list holds.
        String sql = "SELECT typname FROM pg_catalog.pg_type "
                + "WHERE typname = ANY(?) ORDER BY typname";

        // createArrayOf builds a JDBC array of the named element type,
        // which setArray sends as a PostgreSQL array. Array is not
        // AutoCloseable, so the finally block calls free() to release it.
        Array array = conn.createArrayOf("text", names);
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setArray(1, array);

            try (ResultSet rs = stmt.executeQuery()) {
                List<String> found = new ArrayList<>();
                while (rs.next()) {
                    found.add(rs.getString(1));
                }
                return found;
            }
        } finally {
            array.free();
        }
    }
    // --8<-- [end:query]

    // --8<-- [start:main]
    public static void main(String[] args) {
        String[] wanted = {"int4", "text", "bool", "no_such_type"};

        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            List<String> found = findTypes(conn, wanted);
            System.out.println("Found " + found.size() + " of "
                    + wanted.length + " types: " + String.join(", ", found));
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
