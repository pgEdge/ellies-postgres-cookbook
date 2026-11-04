# Ellie's Postgres Cookbook
# Passing a list of values as a single array parameter, using the pg gem.
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
# Returns the names from the list that exist as data types.
def find_types(conn, names)
  # The whole list travels as one array parameter, so the SQL text is the
  # same however many values the list holds. PG::TextEncoder::Array turns
  # a Ruby array into the text form of a PostgreSQL array, quoting each
  # element as needed.
  encoder = PG::TextEncoder::Array.new
  result = conn.exec_params(
    "SELECT typname FROM pg_catalog.pg_type " \
    "WHERE typname = ANY($1) ORDER BY typname",
    [encoder.encode(names)]
  )

  result.column_values(0)
end
# --8<-- [end:query]

# --8<-- [start:main]
wanted = ["int4", "text", "bool", "no_such_type"]

begin
  conn = connect
  found = find_types(conn, wanted)
  puts "Found #{found.length} of #{wanted.length} types: #{found.join(', ')}"
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
