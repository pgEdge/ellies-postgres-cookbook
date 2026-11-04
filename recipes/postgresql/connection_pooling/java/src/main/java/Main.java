/*
 * Ellie's Postgres Cookbook
 * Using a connection pool, with JDBC and HikariCP.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.pool.HikariPool.PoolInitializationException;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
// --8<-- [end:imports]

public class Main {

    // --8<-- [start:config]
    /** The most connections that the pool opens at any one time. */
    static final int POOL_SIZE = 2;

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
    // --8<-- [end:config]

    // --8<-- [start:pool]
    /** Creates a pool that holds at most POOL_SIZE connections. */
    static HikariDataSource createPool() {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(connectionUrl());
        config.setUsername(envOr("PGUSER", "postgres"));

        // The password is omitted if PGPASSWORD is unset or empty.
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            config.setPassword(password);
        }

        config.setMaximumPoolSize(POOL_SIZE);

        // A request for a connection fails after this many milliseconds
        // if the pool can neither lend an idle connection nor open a new
        // one.
        config.setConnectionTimeout(5000);

        // The constructor opens the first connection, and throws a
        // PoolInitializationException if the server is unreachable.
        return new HikariDataSource(config);
    }
    // --8<-- [end:pool]

    // --8<-- [start:query]
    /** Borrows a connection from the pool, and returns the number back. */
    static int runQuery(HikariDataSource pool, int number)
            throws SQLException {
        // Pass values as parameters rather than concatenating them into
        // the SQL string. The cast gives the parameter a type, which the
        // server cannot infer from SELECT ? alone.
        String sql = "SELECT ?::int";

        // try-with-resources returns the connection to the pool when the
        // block exits, whether or not an error occurred; closing a pooled
        // connection does not disconnect it from the server.
        try (Connection conn = pool.getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, number);

            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    // --8<-- [end:query]

    // --8<-- [start:main]
    public static void main(String[] args) {
        // try-with-resources closes the pool, and every connection in it,
        // when the block exits, whether or not an error occurred.
        try (HikariDataSource pool = createPool()) {
            // Five threads ask for a connection at once, but the pool has
            // only two, so the other threads wait their turn.
            ExecutorService executor = Executors.newFixedThreadPool(5);
            List<Future<Integer>> futures = new ArrayList<>();
            try {
                for (int n = 1; n <= 5; n++) {
                    int number = n;
                    futures.add(
                        executor.submit(() -> runQuery(pool, number)));
                }

                int sum = 0;
                for (Future<Integer> future : futures) {
                    sum += future.get();
                }
                System.out.println("Ran " + futures.size()
                        + " queries through a pool of at most "
                        + POOL_SIZE + " connections");
                System.out.println("Sum of results: " + sum);
            } finally {
                executor.shutdown();
            }
        // A query that fails inside a thread arrives wrapped in an
        // ExecutionException. The pool throws PoolInitializationException
        // if it cannot open its first connection.
        } catch (ExecutionException e) {
            System.err.println("Database error: " + e.getCause().getMessage());
            System.exit(1);
        } catch (PoolInitializationException | InterruptedException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    // --8<-- [end:main]
}
