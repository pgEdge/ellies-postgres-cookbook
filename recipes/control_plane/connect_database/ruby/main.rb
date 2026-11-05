# Ellie's Postgres Cookbook
# Finding the address of a pgEdge Control Plane database and connecting
# to it, using Net::HTTP and the pg gem.
#
# These examples are for the Control Plane v0.11.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "pg"
require "uri"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# The password has no default; the Control Plane never returns it, so it
# comes from whoever created the database user.
BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)

TIMEOUT_SECONDS = 30

# Raised when the Control Plane rejects a request or replies oddly.
class ControlPlaneError < StandardError; end

# Fetches a path from the server, and returns the decoded reply.
def get(http, path)
  response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
  unless response.is_a?(Net::HTTPSuccess)
    raise ControlPlaneError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
  end

  begin
    body = JSON.parse(response.body.to_s)
    return body if body.is_a?(Hash)
  rescue JSON::ParserError
    # The body is not JSON; report it below.
  end
  raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
end
# --8<-- [end:config]

# --8<-- [start:find]
# Returns the connection settings for the first instance of the database
# that is available. Each instance runs one node of the database, and its
# connection_info holds the addresses and port that clients use.
def find_instance(http)
  database = get(http, "/v1/databases/#{DATABASE_ID}")
  (database["instances"] || []).each do |instance|
    info = instance["connection_info"] || {}
    next unless instance["state"] == "available" && !(info["addresses"] || []).empty?

    return {
      node: instance["node_name"],
      host: info["addresses"].first,
      port: info["port"],
      dbname: (database["spec"] || {})["database_name"]
    }
  end
  raise ControlPlaneError, "no available instance of #{DATABASE_ID}"
end
# --8<-- [end:find]

# --8<-- [start:connect]
# Connects to the instance, and returns the name of the database and the
# version of the Spock extension.
def query(instance)
  conn = PG.connect(
    host: instance[:host], port: instance[:port], dbname: instance[:dbname],
    user: DATABASE_USER, password: DATABASE_PASSWORD,
    connect_timeout: TIMEOUT_SECONDS
  )
  begin
    database = conn.exec("SELECT current_database()").getvalue(0, 0)
    spock = conn.exec("SELECT extversion FROM pg_extension WHERE extname = 'spock'")
    [database, spock.ntuples.zero? ? "not installed" : spock.getvalue(0, 0)]
  ensure
    # Close the connection whether or not a query failed.
    conn.close
  end
end
# --8<-- [end:connect]

# --8<-- [start:main]
if DATABASE_PASSWORD.nil?
  warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
  exit 1
end

begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  instance = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https", read_timeout: TIMEOUT_SECONDS
  ) { |http| find_instance(http) }
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "Control Plane error: #{e.message}"
  exit 1
end
puts "Connecting to node #{instance[:node]}"

begin
  database, spock = query(instance)
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
end
puts "Connected to database #{database}"
puts "Spock: #{spock}"
# --8<-- [end:main]
