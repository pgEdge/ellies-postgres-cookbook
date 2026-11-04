# Ellie's Postgres Cookbook
# Connecting to PostgreSQL and running a scalar query, using the pg gem.
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

# --8<-- [start:query]
# Returns the number of data types with the given name.
def count_types(conn, name)
  # Always pass values as parameters rather than interpolating them into
  # the SQL string; the pg gem sends them separately, which prevents SQL
  # injection.
  result = conn.exec_params(
    "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
    [name]
  )

  # Results arrive as strings, so convert the value to an Integer.
  result.getvalue(0, 0).to_i
end
# --8<-- [end:query]

# --8<-- [start:main]
begin
  conn = connect
  count = count_types(conn, "int4")
  puts "Number of types named 'int4': #{count}"
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
