# Ellie's Postgres Cookbook
# Storing and searching vectors with pgvector, using the pg gem.
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

# --8<-- [start:schema]
# Enables pgvector and creates a temporary table of colours.
def create_schema(conn)
  conn.exec("CREATE EXTENSION IF NOT EXISTS vector")

  # vector(3) fixes the number of dimensions, one for each of the red,
  # green, and blue components. The temporary table disappears when the
  # session ends, so the program can run repeatedly.
  conn.exec("CREATE TEMPORARY TABLE colours (" \
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)")

  # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
  # matches the <-> (Euclidean distance) operator used by the search.
  conn.exec("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
end
# --8<-- [end:schema]

# --8<-- [start:insert]
# Stores five colours, each as a vector of its RGB components.
def insert_colours(conn)
  colours = [
    ["red", "[1,0,0]"],
    ["green", "[0,1,0]"],
    ["blue", "[0,0,1]"],
    ["yellow", "[1,1,0]"],
    ["white", "[1,1,1]"]
  ]
  colours.each do |name, rgb|
    # A vector travels as text in pgvector's [x,y,z] format, and the
    # ::vector cast converts it on the server, so the gem needs no
    # vector-specific support.
    conn.exec_params(
      "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
      [name, rgb]
    )
  end
end
# --8<-- [end:insert]

# --8<-- [start:search]
# Returns the names of the colours nearest to the target vector.
def nearest_colours(conn, target, count)
  # <-> is the Euclidean (L2) distance operator, so ordering by it puts
  # the nearest colour first.
  result = conn.exec_params(
    "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
    [target, count]
  )
  result.map { |row| row["name"] }
end
# --8<-- [end:search]

# --8<-- [start:main]
begin
  target = "[0.9,0.7,0.2]"
  conn = connect
  create_schema(conn)
  insert_colours(conn)

  puts "Colours nearest to #{target}:"
  nearest_colours(conn, target, 3).each_with_index do |name, i|
    puts "#{i + 1}. #{name}"
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
