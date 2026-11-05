# Ellie's Postgres Cookbook
# Searching by meaning through the pgEdge Postgres MCP Server, using
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

# The server turns the query into an embedding before it searches, which
# can take a while if the embedding model has to load first, so the
# timeout is longer than in the other recipes.
TIMEOUT_SECONDS = 90

QUERY = "a gift for an amateur astronomer"

# Raised when the MCP Server rejects a request or replies oddly.
class McpError < StandardError; end

# Parses a reply as a JSON object, or returns nil if it is not one.
def parse_object(text)
  body = JSON.parse(text.to_s)
  body.is_a?(Hash) ? body : nil
rescue JSON::ParserError
  nil
end

# Calls a tool with tools/call and returns the text of its reply. The
# server answers a JSON-RPC error with HTTP status 200, and a tool that
# fails returns a normal result with isError set, so the method checks for
# both as well as the HTTP status.
def call_tool(http, name, arguments)
  request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
  request["Authorization"] = "Bearer #{TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/call",
                                 params: { name: name, arguments: arguments } })
  response = http.request(request)
  unless response.code == "200"
    raise McpError, "#{name} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
  end

  reply = parse_object(response.body)
  unless reply && (reply.key?("result") || reply.key?("error"))
    raise McpError, "#{name} failed: unexpected response: #{response.body.to_s[0, 200]}"
  end
  raise McpError, "#{name} failed: #{reply["error"]["message"]}" if reply.key?("error")

  result = reply["result"]
  text = result.is_a?(Hash) ? result.dig("content", 0, "text") : nil
  raise McpError, "#{name} failed: unexpected result: #{response.body.to_s[0, 200]}" unless text.is_a?(String)
  raise McpError, "#{name} failed: #{text}" if result["isError"]

  text
end
# --8<-- [end:config]

# --8<-- [start:search]
# Searches the product descriptions for the query, and prints the number
# of results and the name of the product that matches it most closely.
# similarity_search finds the closest rows by vector distance, and then
# reorders them, mixing in a keyword score and favouring variety, so the
# first result in the reply is not always the closest. Each result has a
# line such as "Source: cookbook_mcp.products.description (vector search
# rank: #1, chunk: 1)"; the method picks the result ranked first by the
# vector search, whose text follows the first blank line after it. Every
# description starts with the product's name and a colon.
def search(http)
  text = call_tool(http, "similarity_search", {
                     table_name: "cookbook_mcp.products",
                     query_text: QUERY,
                     top_n: 3
                   })
  puts "Query: #{QUERY}"
  # A limit of -1 keeps empty strings at the end.
  lines = text.split("\n", -1)
  puts "Results: #{lines.count { |line| line.match?(%r{\AResult \d+/\d+\z}) }}"

  source = lines.index do |line|
    line.start_with?("Source: ") && line.end_with?("(vector search rank: #1, chunk: 1)")
  end
  blank = source && (source + 1...lines.length).find { |i| lines[i].empty? }
  best = blank ? lines[blank + 1].to_s : ""
  raise McpError, "The reply had no closest match: #{text[0, 200]}" unless best.include?(": ")

  puts "Best match: #{best.split(": ", 2).first}"
end
# --8<-- [end:search]

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
    search(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "MCP Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
