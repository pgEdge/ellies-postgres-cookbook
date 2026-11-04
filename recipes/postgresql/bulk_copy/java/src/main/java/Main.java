/*
 * Ellie's Postgres Cookbook
 * Loading rows in bulk with COPY, using JDBC and the PostgreSQL JDBC
 * driver (pgJDBC).
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Properties;

import org.postgresql.PGConnection;
import org.postgresql.copy.CopyIn;
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

    // --8<-- [start:create_table]
    /**
     * Creates a temporary table, which only this session can see and
     * which PostgreSQL drops when the session ends.
     */
    static void createTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE items ("
                    + "id int PRIMARY KEY, name text NOT NULL)");
        }
    }
    // --8<-- [end:create_table]

    // --8<-- [start:generate_rows]
    /**
     * Escapes a value for the COPY text format, in which a backslash, a
     * tab, a newline, and a carriage return all have a special meaning.
     */
    static String escapeText(String value) {
        return value
                .replace("\\", "\\\\")
                .replace("\t", "\\t")
                .replace("\n", "\\n")
                .replace("\r", "\\r");
    }

    /**
     * Formats the row with the given id as one line of COPY text: the
     * columns are separated by a tab, and the row ends with a newline.
     */
    static byte[] formatRow(int id) {
        String line = id + "\t" + escapeText("item " + id) + "\n";
        return line.getBytes(StandardCharsets.UTF_8);
    }
    // --8<-- [end:generate_rows]

    // --8<-- [start:copy_rows]
    /**
     * Loads rows with ids 1 to count using COPY ... FROM STDIN, and
     * returns how many rows the server stored.
     */
    static long copyRows(Connection conn, int count) throws SQLException {
        // The copy API belongs to the PostgreSQL driver rather than to
        // JDBC, so unwrap() reaches it from the standard Connection.
        PGConnection pgConn = conn.unwrap(PGConnection.class);
        CopyIn copy = pgConn.getCopyAPI().copyIn(
                "COPY items (id, name) FROM STDIN");

        try {
            // Send the rows one at a time. The driver buffers the data,
            // so this is much faster than one INSERT for each row, and
            // the program never holds more than one row.
            for (int id = 1; id <= count; id++) {
                byte[] line = formatRow(id);
                copy.writeToCopy(line, 0, line.length);
            }

            // endCopy() finishes the copy, and returns the row count.
            return copy.endCopy();
        } finally {
            // If an error left the copy unfinished, cancel it so that the
            // connection becomes usable again.
            if (copy.isActive()) {
                copy.cancelCopy();
            }
        }
    }
    // --8<-- [end:copy_rows]

    // --8<-- [start:summarise]
    /**
     * Prints the number of rows in the table and the sum of their ids.
     */
    static void summarise(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                     "SELECT count(*), sum(id) FROM items")) {
            rs.next();
            System.out.println("Rows in table: " + rs.getLong(1));
            System.out.println("Sum of ids: " + rs.getLong(2));
        }
    }
    // --8<-- [end:summarise]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            createTable(conn);

            long copied = copyRows(conn, 1000);
            System.out.println("Copied " + copied + " rows");

            summarise(conn);
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
