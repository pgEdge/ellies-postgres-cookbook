# Ellie's Postgres Cookbook
# Setting a server-side statement timeout, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# The SQLSTATE code that the server reports when it cancels a statement,
# whether because of a timeout or because a client asked for the cancel.
QUERY_CANCELED = "57014"

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
# BEGIN, so a cancelled statement does not leave the session in a failed
# transaction.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:timeout]
# Sets the statement timeout for the rest of the session.
def set_statement_timeout(conn, timeout)
  # SET cannot take a parameter, but set_config() is an ordinary
  # function, so the value can be sent safely. The final argument, false,
  # makes the setting last for the session rather than for the current
  # transaction.
  conn.exec_params("SELECT set_config('statement_timeout', $1, false)",
                   [timeout])
end

# Runs a statement that outlasts the timeout, and returns true if the
# server cancelled it.
def sleep_exceeds_timeout?(conn)
  conn.exec("SELECT pg_sleep(5)")
  false
rescue PG::Error => e
  # Only a cancelled statement is expected here; any other error is a
  # real failure, so it is raised again.
  raise unless e.result&.error_field(PG::PG_DIAG_SQLSTATE) == QUERY_CANCELED

  true
end

# Returns true if the session can still run a statement.
def usable?(conn)
  conn.exec("SELECT 1").getvalue(0, 0).to_i == 1
end
# --8<-- [end:timeout]

# --8<-- [start:main]
begin
  conn = connect
  set_statement_timeout(conn, "100ms")
  if sleep_exceeds_timeout?(conn)
    puts "Query cancelled after exceeding the statement timeout"
  end
  puts "Connection still usable: #{usable?(conn)}"
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
