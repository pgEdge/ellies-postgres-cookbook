/*
 * Ellie's Postgres Cookbook
 * Listening for notifications with LISTEN and NOTIFY, using JDBC and the
 * PostgreSQL JDBC driver (pgJDBC).
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Properties;

import org.postgresql.PGConnection;
import org.postgresql.PGNotification;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    static final String CHANNEL = "cookbook_listen_notify";
    static final int TIMEOUT_MILLIS = 5000;

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
     * Opens a connection with the settings from the environment. JDBC
     * connections start in autocommit mode, so LISTEN takes effect, and
     * NOTIFY is delivered, as soon as each statement completes.
     */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    // --8<-- [end:connect]

    // --8<-- [start:listen]
    /** Subscribes the connection to a channel. */
    static void listen(Connection conn, String channel)
            throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            // LISTEN takes an identifier rather than a value, so it cannot
            // use a parameter; enquoteIdentifier quotes the name safely.
            stmt.execute("LISTEN " + stmt.enquoteIdentifier(channel, true));
        }
    }
    // --8<-- [end:listen]

    // --8<-- [start:notify]
    /** Sends a notification to every connection listening on a channel. */
    static void notify(Connection conn, String channel, String payload)
            throws SQLException {
        // pg_notify() takes the channel and payload as ordinary
        // parameters, unlike the NOTIFY command.
        try (PreparedStatement stmt =
                conn.prepareStatement("SELECT pg_notify(?, ?)")) {
            stmt.setString(1, channel);
            stmt.setString(2, payload);
            stmt.execute();
        }
    }
    // --8<-- [end:notify]

    // --8<-- [start:wait]
    /**
     * Waits for a notification, and returns it, or null on timeout.
     * PGConnection is the pgJDBC extension interface, which unwrap()
     * returns from the standard Connection.
     */
    static PGNotification waitForNotification(Connection conn,
                                              int timeoutMillis)
            throws SQLException {
        PGNotification[] received =
                conn.unwrap(PGConnection.class).getNotifications(timeoutMillis);
        return (received == null || received.length == 0) ? null : received[0];
    }
    // --8<-- [end:wait]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes both connections when the block exits,
        // whether or not an error occurred.
        try (Connection listener = connect(); Connection sender = connect()) {
            listen(listener, CHANNEL);
            System.out.println("Listening on channel '" + CHANNEL + "'");

            notify(sender, CHANNEL, "Hello from connection B");

            PGNotification message =
                    waitForNotification(listener, TIMEOUT_MILLIS);
            if (message == null) {
                System.err.println("No notification within "
                        + TIMEOUT_MILLIS / 1000 + " seconds");
                System.exit(1);
            }
            System.out.println("Received notification on '"
                    + message.getName() + "': " + message.getParameter());
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
