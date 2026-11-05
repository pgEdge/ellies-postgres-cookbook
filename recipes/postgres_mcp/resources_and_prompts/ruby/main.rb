# Ellie's Postgres Cookbook
# Reading resources and prompts from the pgEdge Postgres MCP Server, using
# Net::HTTP.
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

# Sends a JSON-RPC request and returns its result. The server answers a
# JSON-RPC error with HTTP status 200, so the method checks the reply for
# an error member as well as the HTTP status.
def rpc(http, method, params)
  request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
  request["Authorization"] = "Bearer #{TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: method, params: params })
  response = http.request(request)
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

# --8<-- [start:resources]
# Lists the resources that the server offers, and then reads
# pg://system_info, which describes the PostgreSQL server. The contents of
# a resource are text, which for this one holds a JSON object, so the
# method parses the text a second time. version_number is a string such as
# "180006", from which integer division by 10000 gives the major version.
def read_system_info(http)
  list = rpc(http, "resources/list", {})
  puts "Resources: #{Array(list["resources"]).map { |r| r["uri"] }.join(", ")}"

  result = rpc(http, "resources/read", { uri: "pg://system_info" })
  info = parse_object(result.dig("contents", 0, "text"))
  version_number = Integer(info["version_number"], exception: false) if info
  unless version_number && [true, false].include?(info["allow_writes"])
    raise McpError, "Unexpected result: #{result.to_s[0, 200]}"
  end

  puts "PostgreSQL major version: #{version_number / 10_000}"
  puts "Writes allowed: #{info["allow_writes"]}"
end
# --8<-- [end:resources]

# --8<-- [start:prompts]
# Lists the prompts that the server offers, and then fetches
# explore-database, which takes no arguments. A prompt is a set of
# messages, ready to hand to a language model, that guide it through a
# task with the server's tools.
def read_prompts(http)
  list = rpc(http, "prompts/list", {})
  puts "Prompts: #{Array(list["prompts"]).map { |p| p["name"] }.join(", ")}"

  prompt = rpc(http, "prompts/get", { name: "explore-database", arguments: {} })
  role = prompt.dig("messages", 0, "role")
  raise McpError, "Unexpected result: #{prompt.to_s[0, 200]}" unless role.is_a?(String)

  puts "explore-database: #{prompt["description"]}"
  puts "First message role: #{role}"
end
# --8<-- [end:prompts]

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
    read_system_info(http)
    read_prompts(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "MCP Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
