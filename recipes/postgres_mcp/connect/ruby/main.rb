# Ellie's Postgres Cookbook
# Connecting to the pgEdge Postgres MCP Server, using Net::HTTP.
#
# These examples are for pgEdge Postgres MCP Server 1.1.0.
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

BASE_URL = env_or("MCP_URL", "http://localhost:8080").sub(%r{/+\z}, "")
TOKEN = env_or("MCP_TOKEN", "")

TIMEOUT_SECONDS = 30

# Raised when the MCP Server rejects a request or replies oddly.
class McpError < StandardError; end

# Parses a reply as a JSON object, or returns nil if it is not one.
def parse_object(text)
  body = JSON.parse(text.to_s)
  body.is_a?(Hash) ? body : nil
rescue JSON::ParserError
  nil
end

# Posts a JSON-RPC message to the MCP endpoint with a token, and returns
# the response.
def post(http, token, message)
  request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(message)
  http.request(request)
end

# Sends a JSON-RPC request and returns its result. The server answers a
# JSON-RPC error with HTTP status 200, so the method checks the reply for
# an error member as well as the HTTP status.
def rpc(http, method, params)
  response = post(http, TOKEN, { jsonrpc: "2.0", id: 1, method: method, params: params })
  unless response.code == "200"
    raise McpError, "#{method} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
  end

  reply = parse_object(response.body)
  unless reply && (reply.key?("result") || reply.key?("error"))
    raise McpError, "#{method} failed: unexpected response: #{response.body.to_s[0, 200]}"
  end
  raise McpError, "#{method} failed: #{reply["error"]["message"]}" if reply.key?("error")

  reply["result"]
end
# --8<-- [end:config]

# --8<-- [start:health]
# Checks that the server is running. The /health endpoint needs no token.
def check_health(http)
  response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}/health")))
  unless response.code == "200"
    raise McpError, "Health check failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
  end
  unless parse_object(response.body)&.fetch("status", nil) == "ok"
    raise McpError, "Unexpected response: #{response.body.to_s[0, 200]}"
  end

  puts "Health: ok"
end
# --8<-- [end:health]

# --8<-- [start:initialize]
# Introduces the client to the server, and prints the server's name and
# version and the protocol revision that the server chose. The server
# accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
# revision it does not know with one that it does, so the client checks
# the answer. The notifications/initialized message then completes the
# handshake; it is a notification, with no id, so the server replies with
# HTTP 202 and no body.
def initialize_session(http)
  result = rpc(http, "initialize", {
                 protocolVersion: "2025-06-18",
                 capabilities: {},
                 clientInfo: { name: "cookbook", version: "1.0.0" }
               })
  info = result.is_a?(Hash) ? result["serverInfo"] : nil
  unless info.is_a?(Hash) && info["name"].is_a?(String) && info["version"].is_a?(String)
    raise McpError, "Unexpected result: #{result}"
  end

  puts "Server: #{info["name"]} #{info["version"]}"
  protocol = result["protocolVersion"]
  raise McpError, "The server chose protocol version #{protocol}" unless protocol == "2025-06-18"

  puts "Protocol version: #{protocol}"

  response = post(http, TOKEN, { jsonrpc: "2.0", method: "notifications/initialized" })
  return if response.code == "202"

  raise McpError, "notifications/initialized failed with HTTP #{response.code}: " \
                  "#{response.body.to_s[0, 200]}"
end
# --8<-- [end:initialize]

# --8<-- [start:wrong_token]
# Sends a request with a token that the server does not know, and prints
# the HTTP status and the server's message, which is a JSON object with an
# error member rather than a JSON-RPC reply.
def wrong_token(http)
  response = post(http, "not-a-real-token",
                  { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
  unless response.code == "401"
    raise McpError, "Expected HTTP 401 for a wrong token, but got #{response.code}"
  end

  message = parse_object(response.body)&.fetch("error", nil)
  message = "no message" if message.nil? || message.to_s.empty?
  puts "Wrong token: HTTP #{response.code}, #{message}"
end
# --8<-- [end:wrong_token]

# --8<-- [start:main]
if TOKEN.empty?
  warn "MCP_TOKEN must be set"
  exit 1
end

begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) do |http|
    check_health(http)
    initialize_session(http)
    wrong_token(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "MCP Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
