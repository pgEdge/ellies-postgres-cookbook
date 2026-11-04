# Ellie's Postgres Cookbook
# Inserting rows and reading generated keys, using the pg gem.
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

# --8<-- [start:setup]
# Creates a temporary table whose id column the server fills in.
# GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
# sequence, and refuses any attempt to supply one.
def create_people(conn)
  conn.exec(
    "CREATE TEMPORARY TABLE people (" \
    "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " \
    "name text NOT NULL)"
  )
end
# --8<-- [end:setup]

# --8<-- [start:add_person]
# Inserts a row and returns the id that the server generated.
def add_person(conn, name)
  # RETURNING makes the INSERT produce a result row, like a SELECT, so the
  # program learns the new id without a second query. The name is a
  # parameter, which the pg gem sends separately from the SQL text.
  result = conn.exec_params(
    "INSERT INTO people (name) VALUES ($1) RETURNING id",
    [name]
  )

  # Results arrive as strings, so convert the value to an Integer.
  result.getvalue(0, 0).to_i
end
# --8<-- [end:add_person]

# --8<-- [start:main]
begin
  conn = connect
  create_people(conn)
  ["Jane Doe", "John Smith", "Alex Example"].each do |name|
    id = add_person(conn, name)
    puts "Inserted '#{name}' with id #{id}"
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
