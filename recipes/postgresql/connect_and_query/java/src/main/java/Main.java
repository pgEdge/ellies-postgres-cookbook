/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL and running a scalar query, using JDBC and
 * the PostgreSQL JDBC driver (pgJDBC).
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
import java.util.Properties;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }

    public static void main(String[] args) {
        // JDBC identifies the server with a URL, and takes the user name
        // and password as connection properties.
        String url = "jdbc:postgresql://"
                + envOr("PGHOST", "localhost") + ":"
                + envOr("PGPORT", "5432") + "/"
                + envOr("PGDATABASE", "postgres");

        Properties props = new Properties();
        props.setProperty("user", envOr("PGUSER", "postgres"));
        String password = System.getenv("PGPASSWORD");
        if (password != null) {
            props.setProperty("password", password);
        }
        // --8<-- [end:config]

        // --8<-- [start:connect]
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = DriverManager.getConnection(url, props)) {
            // --8<-- [end:connect]
            // --8<-- [start:query]
            // Always pass values as parameters rather than concatenating
            // them into the SQL string; the driver sends them separately,
            // which prevents SQL injection.
            String sql =
                "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = ?";

            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, "int4");

                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    long count = rs.getLong(1);

                    System.out.println(
                        "Number of types named 'int4': " + count);
                }
            }
            // --8<-- [end:query]
        // --8<-- [start:errors]
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
        // --8<-- [end:errors]
    }
}
