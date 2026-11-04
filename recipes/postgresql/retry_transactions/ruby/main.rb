# Ellie's Postgres Cookbook
# Retrying a transaction after a serialisation failure, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# The SQLSTATE codes that mean "run the transaction again": 40001 is a
# serialisation failure and 40P01 is a deadlock.
RETRYABLE = %w[40001 40P01].freeze
MAX_ATTEMPTS = 5

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
# Opens a connection with the settings from the environment. The server
# runs each statement in its own transaction unless the program sends
# BEGIN, so the program decides where each transaction starts and ends.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:setup]
# Drops the shared counter table if it exists.
def drop_table(conn)
  conn.exec("DROP TABLE IF EXISTS cookbook_retry_transactions")
end

# Creates the shared counter table, with a single row set to zero. The
# table must be visible to a second connection, so it cannot be
# temporary; the name is specific to this recipe, and any earlier copy is
# dropped first.
def create_table(conn)
  drop_table(conn)
  conn.exec("CREATE TABLE cookbook_retry_transactions " \
            "(id int PRIMARY KEY, value int NOT NULL)")
  conn.exec_params(
    "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
    [1, 0]
  )
end
# --8<-- [end:setup]

# --8<-- [start:work]
# Reads the counter and writes back the value plus one.
def increment_counter(conn, attempt)
  value = read_counter(conn)

  # Simulate another client by updating the row from a second connection,
  # after this transaction has read the row but before it writes. This
  # happens on the first attempt only.
  if attempt == 1
    other = connect
    begin
      other.exec_params(
        "UPDATE cookbook_retry_transactions SET value = value + 1 " \
        "WHERE id = $1",
        [1]
      )
    ensure
      other.close
    end
  end

  # Under REPEATABLE READ, updating a row that another transaction
  # changed and committed since this transaction's snapshot was taken
  # fails with SQLSTATE 40001.
  conn.exec_params(
    "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
    [value + 1, 1]
  )
end

# Returns the current value of the counter. Results arrive as strings, so
# the value is converted to an Integer.
def read_counter(conn)
  conn.exec_params(
    "SELECT value FROM cookbook_retry_transactions WHERE id = $1", [1]
  ).getvalue(0, 0).to_i
end
# --8<-- [end:work]

# --8<-- [start:retry]
# Returns the SQLSTATE code of an error reported by the server, or nil for
# errors such as a lost connection that have no result.
def sqlstate(error)
  error.result&.error_field(PG::PG_DIAG_SQLSTATE)
end

# Yields the connection and the attempt number inside a REPEATABLE READ
# transaction, and runs the block again if the server reports a
# serialisation failure or a deadlock.
def run_with_retry(conn)
  (1..MAX_ATTEMPTS).each do |attempt|
    begin
      conn.exec("BEGIN ISOLATION LEVEL REPEATABLE READ")
      yield conn, attempt
      conn.exec("COMMIT")
      puts "Attempt #{attempt}: committed"
      return
    rescue PG::Error => e
      # End the failed transaction so that the session can start another.
      # If the connection is lost the rollback fails too, and that error
      # must not hide the original one.
      begin
        conn.exec("ROLLBACK")
      rescue PG::Error
        nil
      end

      # Any other error, or running out of attempts, is a real failure
      # that the caller must handle.
      raise unless RETRYABLE.include?(sqlstate(e)) && attempt < MAX_ATTEMPTS

      puts "Attempt #{attempt}: serialisation failure, retrying"
      # A short, growing pause gives the competing transaction time to
      # finish.
      sleep(0.05 * attempt)
    end
  end
end
# --8<-- [end:retry]

# --8<-- [start:main]
begin
  conn = connect
  begin
    create_table(conn)
    run_with_retry(conn) { |c, attempt| increment_counter(c, attempt) }
    puts "Counter value: #{read_counter(conn)}"
  ensure
    # Drop the shared table even if the work failed.
    drop_table(conn)
  end
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
