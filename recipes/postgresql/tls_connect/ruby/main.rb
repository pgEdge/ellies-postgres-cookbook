# Ellie's Postgres Cookbook
# Connecting to PostgreSQL over TLS with full verification, using the pg
# gem.
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
  # PGSSLROOTCERT has no default, because verification is meaningless
  # without the certificate of the authority that signed the server
  # certificate.
  root_cert = env_or("PGSSLROOTCERT", nil)
  raise ArgumentError, "PGSSLROOTCERT must name the root certificate" unless root_cert

  {
    host: env_or("PGHOST", "localhost"),
    port: env_or("PGPORT", "5432"),
    dbname: env_or("PGDATABASE", "postgres"),
    user: env_or("PGUSER", "postgres"),
    password: env_or("PGPASSWORD", nil),
    # verify-full checks that the certificate chains to the root
    # certificate and that it matches the host name. Weaker modes, such
    # as require, encrypt the connection without proving who is on the
    # other end.
    sslmode: "verify-full",
    sslrootcert: root_cert
  }.compact
end
# --8<-- [end:config]

# --8<-- [start:connect]
# Opens a verified TLS connection with the settings from the environment.
# The connection fails if verification fails.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:query]
# Asks the server whether this connection uses TLS.
def connection_encrypted?(conn)
  # pg_stat_ssl has one row for each connection; pg_backend_pid()
  # identifies the one that belongs to this session. The version column
  # holds the protocol version, such as TLSv1.3.
  result = conn.exec(
    "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " \
    "WHERE pid = pg_backend_pid()"
  )

  # Results arrive as strings; PostgreSQL writes a boolean as t or f.
  result.getvalue(0, 0) == "t"
end
# --8<-- [end:query]

# --8<-- [start:main]
begin
  conn = connect
  puts "Connection is encrypted: #{connection_encrypted?(conn)}"
  # Reaching this line means that verify-full succeeded; a certificate or
  # host name mismatch raises PG::ConnectionBad instead.
  puts "Server certificate verified: true"
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error, ArgumentError => e
  warn "Database error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. conn is nil if
# the connection attempt failed, hence the safe navigation operator.
ensure
  conn&.close
end
# --8<-- [end:main]
