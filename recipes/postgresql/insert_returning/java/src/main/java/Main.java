/*
 * Ellie's Postgres Cookbook
 * Inserting rows and reading generated keys, using JDBC and the
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
     * Creates a temporary table whose id column the server fills in.
     * GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
     * sequence, and refuses any attempt to supply one.
     */
    static void createPeople(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE people ("
                    + "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
                    + "name text NOT NULL)");
        }
    }
    // --8<-- [end:setup]

    // --8<-- [start:add_person]
    /** Inserts a row and returns the id that the server generated. */
    static int addPerson(Connection conn, String name) throws SQLException {
        // RETURNING makes the INSERT produce a result row, like a SELECT,
        // so the program learns the new id without a second query. The
        // name is a parameter, which the driver sends separately from the
        // SQL text. Because the statement returns rows, the program runs
        // it with executeQuery() rather than executeUpdate().
        String sql = "INSERT INTO people (name) VALUES (?) RETURNING id";

        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, name);

            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    // --8<-- [end:add_person]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            createPeople(conn);
            for (String name : new String[] {
                    "Jane Doe", "John Smith", "Alex Example"}) {
                int id = addPerson(conn, name);
                System.out.println("Inserted '" + name + "' with id " + id);
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
