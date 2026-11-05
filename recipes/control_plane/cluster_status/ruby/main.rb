# Ellie's Postgres Cookbook
# Checking the version of the pgEdge Control Plane, its cluster, and the
# state of each host, using Net::HTTP.
#
# These examples are for the Control Plane v0.11.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "uri"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")

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

# --8<-- [start:version]
# Prints the version of the Control Plane server.
def show_version(http)
  version = get(http, "/v1/version")["version"]
  raise ControlPlaneError, "Unexpected response: missing version" unless version.is_a?(String)

  puts "Version: #{version}"
end
# --8<-- [end:version]

# --8<-- [start:cluster]
# Prints the state of the cluster. A server answers this request only once
# its cluster has been initialised, and it then reports "available"; the
# health of the cluster shows in the state of each host.
def show_cluster(http)
  state = (get(http, "/v1/cluster")["status"] || {})["state"]
  raise ControlPlaneError, "Unexpected response: missing state" unless state.is_a?(String)

  puts "Cluster: #{state}"
end
# --8<-- [end:cluster]

# --8<-- [start:hosts]
# Lists the hosts in the cluster with their states, and returns whether
# every host is "healthy". The other states are "degraded", "unreachable"
# and "unknown".
def show_hosts(http)
  hosts = get(http, "/v1/hosts")["hosts"]
  raise ControlPlaneError, "Unexpected response: missing hosts" unless hosts.is_a?(Array)

  puts "Hosts (#{hosts.length}):"
  hosts.map do |host|
    state = (host["status"] || {}).fetch("state", "unknown")
    puts "- #{host["id"]}: #{state}"
    state == "healthy"
  end.all?
end
# --8<-- [end:hosts]

# --8<-- [start:main]
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  healthy = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) do |http|
    show_version(http)
    show_cluster(http)
    show_hosts(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "Control Plane error: #{e.message}"
  exit 1
end

# Report an unhealthy host with the exit status.
unless healthy
  warn "A host is not healthy"
  exit 1
end
# --8<-- [end:main]
