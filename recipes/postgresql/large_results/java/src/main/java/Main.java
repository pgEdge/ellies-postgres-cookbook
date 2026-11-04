/*
 * Ellie's Postgres Cookbook
 * Reading a large result in batches, using JDBC and the PostgreSQL JDBC
 * driver (pgJDBC).
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
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

    // --8<-- [start:read_batches]
    static final int BATCH_SIZE = 1000;

    /**
     * Reads every row of a large result, one batch at a time, and prints
     * the number of rows and the sum of their values.
     */
    static void readInBatches(Connection conn) throws SQLException {
        long rowsRead = 0;
        long total = 0;

        // The driver streams a result only inside a transaction, so turn
        // off autocommit. With autocommit on, the driver ignores the
        // fetch size and loads all 100,000 rows into memory.
        conn.setAutoCommit(false);

        try (Statement stmt = conn.createStatement()) {
            // The fetch size makes the driver ask the server for 1,000
            // rows at a time, through a cursor that it manages for us.
            stmt.setFetchSize(BATCH_SIZE);

            try (ResultSet rs = stmt.executeQuery(
                    "SELECT g FROM generate_series(1, 100000) AS g")) {
                // next() fetches the following batch whenever the
                // current one has been read.
                while (rs.next()) {
                    rowsRead++;
                    total += rs.getLong(1);
                }
            }
        }

        // End the transaction, which also releases the cursor.
        conn.commit();

        System.out.println("Rows read: " + rowsRead);
        System.out.println("Sum of values: " + total);
    }
    // --8<-- [end:read_batches]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            readInBatches(conn);
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
