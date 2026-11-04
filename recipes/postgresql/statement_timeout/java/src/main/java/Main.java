/*
 * Ellie's Postgres Cookbook
 * Setting a server-side statement timeout, using JDBC and the PostgreSQL
 * JDBC driver (pgJDBC).
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
import java.util.Properties;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /**
     * The SQLSTATE code that the server reports when it cancels a
     * statement, whether because of a timeout or because a client asked
     * for the cancel.
     */
    static final String QUERY_CANCELED = "57014";

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
    /**
     * Opens a connection with the settings from the environment. The
     * connection starts in autocommit mode, where each statement is its
     * own transaction, so a cancelled statement does not leave the
     * session in a failed transaction.
     */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    // --8<-- [end:connect]

    // --8<-- [start:timeout]
    /** Sets the statement timeout for the rest of the session. */
    static void setStatementTimeout(Connection conn, String timeout)
            throws SQLException {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for
        // the current transaction.
        try (PreparedStatement stmt = conn.prepareStatement(
                "SELECT set_config('statement_timeout', ?, false)")) {
            stmt.setString(1, timeout);
            stmt.execute();
        }
    }

    /**
     * Runs a statement that outlasts the timeout, and returns true if the
     * server cancelled it.
     */
    static boolean sleepExceedsTimeout(Connection conn)
            throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("SELECT pg_sleep(5)");
        } catch (SQLException e) {
            // Only a cancelled statement is expected here; any other
            // error is a real failure, so it is thrown again.
            if (!QUERY_CANCELED.equals(e.getSQLState())) {
                throw e;
            }
            return true;
        }
        return false;
    }

    /** Returns true if the session can still run a statement. */
    static boolean isUsable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT 1")) {
            rs.next();
            return rs.getInt(1) == 1;
        }
    }
    // --8<-- [end:timeout]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            setStatementTimeout(conn, "100ms");
            if (sleepExceedsTimeout(conn)) {
                System.out.println(
                    "Query cancelled after exceeding the statement timeout");
            }
            System.out.println("Connection still usable: " + isUsable(conn));
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
