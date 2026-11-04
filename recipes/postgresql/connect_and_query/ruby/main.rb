# Ellie's Postgres Cookbook
# Connecting to PostgreSQL and running a scalar query, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# Read the connection settings from the standard libpq environment
# variables, with defaults suitable for a local development server.
# compact removes the password if PGPASSWORD is not set.
params = {
  host: ENV.fetch("PGHOST", "localhost"),
  port: ENV.fetch("PGPORT", "5432"),
  dbname: ENV.fetch("PGDATABASE", "postgres"),
  user: ENV.fetch("PGUSER", "postgres"),
  password: ENV["PGPASSWORD"]
}.compact
# --8<-- [end:config]

begin
  # --8<-- [start:connect]
  conn = PG.connect(params)
  # --8<-- [end:connect]

  # --8<-- [start:query]
  # Always pass values as parameters rather than interpolating them into
  # the SQL string; the pg gem sends them separately, which prevents SQL
  # injection.
  result = conn.exec_params(
    "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
    ["int4"]
  )

  # Results arrive as strings, so convert the value to an Integer.
  count = result.getvalue(0, 0).to_i

  puts "Number of types named 'int4': #{count}"
  # --8<-- [end:query]
# --8<-- [start:errors]
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
# --8<-- [end:errors]
# --8<-- [start:cleanup]
# The ensure block runs whether or not an error occurred. conn is nil if
# the connection attempt failed, hence the safe navigation operator.
ensure
  conn&.close
  # --8<-- [end:cleanup]
end
