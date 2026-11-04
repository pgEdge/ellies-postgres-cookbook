# Ellie's Postgres Cookbook
# Using a connection pool, with the pg and connection_pool gems.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "connection_pool"
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# The most connections that the pool opens at any one time.
POOL_SIZE = 2

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

# --8<-- [start:pool]
# Creates a pool that holds at most POOL_SIZE connections.
def create_pool
  # The block opens a new connection, and the pool calls it on demand, at
  # most POOL_SIZE times. A request for a connection waits for up to
  # timeout seconds when both connections are busy, and then raises
  # ConnectionPool::TimeoutError.
  ConnectionPool.new(size: POOL_SIZE, timeout: 5) do
    PG.connect(connection_params)
  end
end
# --8<-- [end:pool]

# --8<-- [start:query]
# Borrows a connection from the pool, and returns the number back.
def run_query(pool, number)
  # The with block borrows a connection and returns it to the pool when it
  # exits, whether or not an error occurred; it does not close it. Pass
  # values as parameters rather than interpolating them into the SQL
  # string. The cast gives the parameter a type, which the server cannot
  # infer from SELECT $1 alone.
  pool.with do |conn|
    conn.exec_params("SELECT $1::int", [number]).getvalue(0, 0).to_i
  end
end
# --8<-- [end:query]

# --8<-- [start:main]
# Ruby prints a stack trace when a thread fails. Thread#value raises the
# same error again in the main thread, where the rescue clause reports it,
# so switch off the duplicate trace.
Thread.report_on_exception = false

begin
  pool = create_pool

  # Five threads ask for a connection at once, but the pool has only two,
  # so the other threads wait their turn. Thread#value waits for a thread
  # to finish and raises any error that the thread raised.
  threads = (1..5).map { |n| Thread.new { run_query(pool, n) } }
  results = threads.map(&:value)

  puts "Ran #{results.size} queries through a pool of at most " \
       "#{POOL_SIZE} connections"
  puts "Sum of results: #{results.sum}"
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
# The pool raises its own error, which is not a PG::Error, when no
# connection becomes free within the timeout.
rescue ConnectionPool::TimeoutError => e
  warn "Database error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. pool is nil if
# it could not be created, and shutdown closes every connection that the
# pool opened.
ensure
  pool&.shutdown { |conn| conn.close }
end
# --8<-- [end:main]
