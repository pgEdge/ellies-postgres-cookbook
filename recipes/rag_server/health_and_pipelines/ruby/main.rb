# Ellie's Postgres Cookbook
# Checking the health of the pgEdge RAG Server and listing its pipelines,
# using Net::HTTP.
#
# These examples are for pgEdge RAG Server 2.0.0.
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

BASE_URL = env_or("RAG_SERVER_URL", "http://localhost:8080").sub(%r{/+\z}, "")

# None of these endpoints calls a language model, but the health check
# contacts each provider, so allow it some time.
TIMEOUT_SECONDS = 30

# Raised when the RAG Server rejects a request or replies oddly.
class RagError < StandardError; end

# Fetches a path from the server, and returns the decoded reply.
def get(http, path)
  response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
  unless response.is_a?(Net::HTTPSuccess)
    raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
  end

  begin
    body = JSON.parse(response.body.to_s)
    return body if body.is_a?(Hash)
  rescue JSON::ParserError
    # The body is not JSON; report it below.
  end
  raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
end
# --8<-- [end:config]

# --8<-- [start:live]
# Checks that the server process is running. The /v1/live endpoint is
# cheap and calls nothing else, so it suits a frequent liveness probe.
def check_live(http)
  body = get(http, "/v1/live")
  raise RagError, "Unexpected response: #{body}" unless body["status"] == "ok"

  puts "Live: ok"
end
# --8<-- [end:live]

# --8<-- [start:health]
# Describes whether a language model provider answered the check.
def describe_provider(provider)
  return "reachable" if provider["reachable"]

  "unreachable (#{provider.fetch("error", "unknown")})"
end

# Checks whether each pipeline can reach its language model providers.
# The /v1/health endpoint answers with HTTP 200 even when a provider is
# down, so the status field is the thing to check: it is "healthy" or
# "degraded". Prints the report, and returns whether the server is
# healthy.
def check_health(http)
  body = get(http, "/v1/health")
  status = body["status"]
  raise RagError, "Unexpected response: #{body}" unless status.is_a?(String)

  puts "Health: #{status}"
  (body["pipelines"] || []).each do |pipeline|
    embedding = describe_provider(pipeline["embedding"] || {})
    completion = describe_provider(pipeline["completion"] || {})
    puts "- #{pipeline["name"]}: embedding #{embedding}, completion #{completion}"
  end
  status == "healthy"
end
# --8<-- [end:health]

# --8<-- [start:pipelines]
# Lists the pipelines that the server offers, with their descriptions.
def list_pipelines(http)
  pipelines = get(http, "/v1/pipelines")["pipelines"]
  raise RagError, "Unexpected response: missing pipelines" unless pipelines.is_a?(Array)

  puts "Pipelines (#{pipelines.length}):"
  pipelines.each do |pipeline|
    description = pipeline["description"]
    description = "(no description)" if description.nil? || description.empty?
    puts "- #{pipeline["name"]}: #{description}"
  end
end
# --8<-- [end:pipelines]

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
    check_live(http)
    result = check_health(http)
    list_pipelines(http)
    result
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end

# A degraded server still answers with HTTP 200, so report it with the
# exit status.
unless healthy
  warn "RAG Server is not healthy"
  exit 1
end
# --8<-- [end:main]
