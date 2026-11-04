# Ellie's Postgres Cookbook
# Listening for notifications with LISTEN and NOTIFY, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
CHANNEL = "cookbook_listen_notify"
TIMEOUT_SECONDS = 5

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
# Opens a connection with the settings from the environment. libpq runs
# each statement in autocommit mode unless the program sends BEGIN, so
# LISTEN takes effect, and NOTIFY is delivered, as soon as the statement
# completes.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:listen]
# Subscribes the connection to a channel.
def listen(conn, channel)
  # LISTEN takes an identifier rather than a value, so it cannot use a
  # parameter; escape_identifier quotes the name safely.
  conn.exec("LISTEN #{conn.escape_identifier(channel)}")
end
# --8<-- [end:listen]

# --8<-- [start:notify]
# Sends a notification to every connection listening on a channel.
def notify(conn, channel, payload)
  # pg_notify() takes the channel and payload as ordinary parameters,
  # unlike the NOTIFY command.
  conn.exec_params("SELECT pg_notify($1, $2)", [channel, payload])
end
# --8<-- [end:notify]

# --8<-- [start:wait]
# Waits for one notification, and returns its channel and payload, or nil
# on timeout.
def wait_for_notification(conn, timeout)
  received = nil
  # wait_for_notify blocks until a notification arrives or the timeout (in
  # seconds) passes, yields the notification to the block, and returns nil
  # on timeout.
  conn.wait_for_notify(timeout) do |channel, _pid, payload|
    received = [channel, payload]
  end
  received
end
# --8<-- [end:wait]

# --8<-- [start:main]
begin
  listener = connect
  sender = connect

  listen(listener, CHANNEL)
  puts "Listening on channel '#{CHANNEL}'"

  notify(sender, CHANNEL, "Hello from connection B")

  channel, payload = wait_for_notification(listener, TIMEOUT_SECONDS)
  if channel.nil?
    warn "No notification within #{TIMEOUT_SECONDS} seconds"
    exit 1
  end
  puts "Received notification on '#{channel}': #{payload}"
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. A connection is
# nil if its connection attempt failed, hence the safe navigation operator.
ensure
  listener&.close
  sender&.close
end
# --8<-- [end:main]
