/*
 * Ellie's Postgres Cookbook
 * Using transactions to move money between accounts, using JDBC and the
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

    // --8<-- [start:setup]
    /**
     * Creates a temporary table of two accounts. The CHECK constraint
     * stops any balance from going below zero.
     */
    static void createAccounts(Connection conn) throws SQLException {
        // The connection is in autocommit mode here, so each statement
        // commits by itself.
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE accounts ("
                    + "id int PRIMARY KEY, "
                    + "balance int NOT NULL CHECK (balance >= 0))");
            stmt.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)");
        }
    }
    // --8<-- [end:setup]

    // --8<-- [start:transfer]
    /** Moves money between two accounts in a single transaction. */
    static void transfer(Connection conn, int source, int target, int amount)
            throws SQLException {
        // JDBC starts in autocommit mode. Turning it off makes the driver
        // open a transaction that lasts until commit() or rollback().
        conn.setAutoCommit(false);
        try {
            // Credit the target first, so that a failure of the debit
            // shows that the rollback undoes the credit as well.
            update(conn,
                    "UPDATE accounts SET balance = balance + ? WHERE id = ?",
                    amount, target);
            update(conn,
                    "UPDATE accounts SET balance = balance - ? WHERE id = ?",
                    amount, source);
            conn.commit();
        } catch (SQLException e) {
            // Undo the work, then pass the original error to the caller.
            conn.rollback();
            throw e;
        } finally {
            conn.setAutoCommit(true);
        }
    }

    /** Runs an UPDATE statement that takes two integer parameters. */
    static void update(Connection conn, String sql, int first, int second)
            throws SQLException {
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, first);
            stmt.setInt(2, second);
            stmt.executeUpdate();
        }
    }
    // --8<-- [end:transfer]

    // --8<-- [start:balance]
    /** Returns the balance of the given account. */
    static int getBalance(Connection conn, int account) throws SQLException {
        String sql = "SELECT balance FROM accounts WHERE id = ?";

        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, account);

            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    // --8<-- [end:balance]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            createAccounts(conn);

            transfer(conn, 1, 2, 30);
            System.out.println("Transferred 30 from account 1 to account 2");

            try {
                transfer(conn, 1, 2, 500);
                System.out.println(
                        "Transferred 500 from account 1 to account 2");
            } catch (SQLException e) {
                // SQLSTATE 23514 is a check constraint violation. The
                // transaction has already been rolled back, so this is an
                // expected outcome; any other error is not, and reaches
                // the handler below.
                if (!"23514".equals(e.getSQLState())) {
                    throw e;
                }
                System.out.println("Transfer of 500 from account 1 to "
                        + "account 2 failed and was rolled back");
            }

            for (int account = 1; account <= 2; account++) {
                System.out.println("Account " + account + " balance: "
                        + getBalance(conn, account));
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
