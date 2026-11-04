# Ellie's Postgres Cookbook
# Reading a large result in batches, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty; libpq also treats an empty variable as unset.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# Returns the connection settings from the standard libpq environment
# variables, with defaults suitable for a local development server.
# compact removes the password if PGPASSWORD is not set.
def connection_params
  {
    host: env_or("PGHOST", "localhost"),
    port: env_or("PGPORT", "5432"),
    dbname: env_or("PGDATABASE", "postgres"),
    user: env_or("PGUSER", "postgres"),
    password: env_or("PGPASSWORD", nil)
  }.compact
end
# --8<-- [end:config]

# --8<-- [start:connect]
# Opens a connection with the settings from the environment.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:read_batches]
BATCH_SIZE = 1000

# Reads every row of a large result, one batch at a time, and returns the
# number of rows and the sum of their values.
def read_in_batches(conn)
  rows_read = 0
  total = 0

  # A cursor lives only inside a transaction, and the transaction method
  # commits when the block ends, or rolls back if the block raises.
  conn.transaction do
    # DECLARE makes the server hold the result and hand out rows only on
    # request. The pg gem would otherwise copy all 100,000 rows into
    # memory before exec returns. A cursor name cannot be a parameter,
    # but this one is a fixed string, not application data.
    conn.exec("DECLARE large_results CURSOR FOR " \
              "SELECT g FROM generate_series(1, 100000) AS g")

    loop do
      # FETCH returns the next batch, and an empty result at the end.
      batch = conn.exec("FETCH #{BATCH_SIZE} FROM large_results")
      break if batch.ntuples.zero?

      batch.each_row do |(value)|
        rows_read += 1
        total += value.to_i
      end
    end

    conn.exec("CLOSE large_results")
  end

  [rows_read, total]
end
# --8<-- [end:read_batches]

# --8<-- [start:main]
begin
  conn = connect
  rows_read, total = read_in_batches(conn)
  puts "Rows read: #{rows_read}"
  puts "Sum of values: #{total}"
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. conn is nil if
# the connection attempt failed, hence the safe navigation operator.
ensure
  conn&.close
end
# --8<-- [end:main]
