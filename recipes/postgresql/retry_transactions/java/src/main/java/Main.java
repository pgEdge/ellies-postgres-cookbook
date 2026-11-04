/*
 * Ellie's Postgres Cookbook
 * Retrying a transaction after a serialisation failure, using JDBC and
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
import java.sql.Statement;
import java.util.Properties;
import java.util.Set;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /**
     * The SQLSTATE codes that mean "run the transaction again": 40001 is
     * a serialisation failure and 40P01 is a deadlock.
     */
    static final Set<String> RETRYABLE = Set.of("40001", "40P01");
    static final int MAX_ATTEMPTS = 5;

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
     * own transaction.
     */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    // --8<-- [end:connect]

    // --8<-- [start:setup]
    /** Drops the shared counter table if it exists. */
    static void dropTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS cookbook_retry_transactions");
        }
    }

    /**
     * Creates the shared counter table, with a single row set to zero.
     * The table must be visible to a second connection, so it cannot be
     * temporary; the name is specific to this recipe, and any earlier
     * copy is dropped first.
     */
    static void createTable(Connection conn) throws SQLException {
        dropTable(conn);
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TABLE cookbook_retry_transactions "
                    + "(id int PRIMARY KEY, value int NOT NULL)");
        }
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO cookbook_retry_transactions (id, value) "
                + "VALUES (?, ?)")) {
            stmt.setInt(1, 1);
            stmt.setInt(2, 0);
            stmt.executeUpdate();
        }
    }
    // --8<-- [end:setup]

    // --8<-- [start:work]
    /** The work done inside one transaction. */
    interface Work {
        void run(Connection conn, int attempt) throws SQLException;
    }

    /** Reads the counter and writes back the value plus one. */
    static void incrementCounter(Connection conn, int attempt)
            throws SQLException {
        int value = readCounter(conn);

        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before
        // it writes. This happens on the first attempt only.
        if (attempt == 1) {
            try (Connection other = connect();
                 PreparedStatement stmt = other.prepareStatement(
                    "UPDATE cookbook_retry_transactions "
                    + "SET value = value + 1 WHERE id = ?")) {
                stmt.setInt(1, 1);
                stmt.executeUpdate();
            }
        }

        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was
        // taken fails with SQLSTATE 40001.
        try (PreparedStatement stmt = conn.prepareStatement(
                "UPDATE cookbook_retry_transactions SET value = ? "
                + "WHERE id = ?")) {
            stmt.setInt(1, value + 1);
            stmt.setInt(2, 1);
            stmt.executeUpdate();
        }
    }

    /** Returns the current value of the counter. */
    static int readCounter(Connection conn) throws SQLException {
        try (PreparedStatement stmt = conn.prepareStatement(
                "SELECT value FROM cookbook_retry_transactions "
                + "WHERE id = ?")) {
            stmt.setInt(1, 1);
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    // --8<-- [end:work]

    // --8<-- [start:retry]
    /**
     * Runs the work in a REPEATABLE READ transaction, and runs it again
     * if the server reports a serialisation failure or a deadlock.
     */
    static void runWithRetry(Connection conn, Work work)
            throws SQLException, InterruptedException {
        // Turning autocommit off makes the driver start a transaction
        // with the first statement, and end it at commit() or rollback().
        conn.setAutoCommit(false);
        conn.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
        try {
            for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
                try {
                    work.run(conn, attempt);
                    conn.commit();
                    System.out.println("Attempt " + attempt + ": committed");
                    return;
                } catch (SQLException e) {
                    // End the failed transaction so that the session can
                    // start another. If the connection is lost the
                    // rollback fails too, and that error must not hide
                    // the original one, so it is attached to it instead.
                    try {
                        conn.rollback();
                    } catch (SQLException rollbackError) {
                        e.addSuppressed(rollbackError);
                    }

                    // Any other error, or running out of attempts, is a
                    // real failure that the caller must handle.
                    if (!RETRYABLE.contains(e.getSQLState())
                            || attempt == MAX_ATTEMPTS) {
                        throw e;
                    }
                    System.out.println("Attempt " + attempt
                            + ": serialisation failure, retrying");
                    // A short, growing pause gives the competing
                    // transaction time to finish.
                    Thread.sleep(50L * attempt);
                }
            }
        } finally {
            conn.setAutoCommit(true);
        }
    }
    // --8<-- [end:retry]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            try {
                createTable(conn);
                runWithRetry(conn, Main::incrementCounter);
                System.out.println("Counter value: " + readCounter(conn));
            } finally {
                // Drop the shared table even if the work failed.
                dropTable(conn);
            }
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("Interrupted while waiting to retry");
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
