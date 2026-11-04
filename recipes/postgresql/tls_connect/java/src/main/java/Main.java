/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL over TLS with full verification, using JDBC and
 * the PostgreSQL JDBC driver (pgJDBC).
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
     * Returns the user name, password, and TLS settings as connection
     * properties; the password is omitted if PGPASSWORD is unset or
     * empty. PGSSLROOTCERT has no default, because verification is
     * meaningless without the certificate of the authority that signed
     * the server certificate.
     */
    static Properties connectionProperties() {
        String rootCert = envOr("PGSSLROOTCERT", null);
        if (rootCert == null) {
            throw new IllegalStateException(
                    "PGSSLROOTCERT must name the root certificate");
        }

        Properties props = new Properties();
        props.setProperty("user", envOr("PGUSER", "postgres"));
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            props.setProperty("password", password);
        }
        // verify-full checks that the certificate chains to the root
        // certificate and that it matches the host name. Weaker modes,
        // such as require, encrypt the connection without proving who is
        // on the other end.
        props.setProperty("sslmode", "verify-full");
        props.setProperty("sslrootcert", rootCert);
        return props;
    }
    // --8<-- [end:config]

    // --8<-- [start:connect]
    /**
     * Opens a verified TLS connection with the settings from the
     * environment. The connection fails if verification fails.
     */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    // --8<-- [end:connect]

    // --8<-- [start:query]
    /** Asks the server whether this connection uses TLS. */
    static boolean connectionIsEncrypted(Connection conn)
            throws SQLException {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version
        // column holds the protocol version, such as TLSv1.3.
        String sql = "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                + "WHERE pid = pg_backend_pid()";

        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            rs.next();
            return rs.getBoolean(1);
        }
    }
    // --8<-- [end:query]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            boolean encrypted = connectionIsEncrypted(conn);
            System.out.println("Connection is encrypted: " + encrypted);
            // Reaching this line means that verify-full succeeded; a
            // certificate or host name mismatch throws instead.
            System.out.println("Server certificate verified: true");
        // SQLException covers connection, certificate, and server errors;
        // IllegalStateException reports a missing PGSSLROOTCERT.
        } catch (SQLException | IllegalStateException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
