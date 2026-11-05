# Ellie's Postgres Cookbook
# Running read-only queries through the pgEdge Postgres MCP Server, using
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

# Calls a tool with tools/call and returns the text of its reply and
# whether the tool failed, which it reports by setting isError. The server
# answers a JSON-RPC error with HTTP status 200, so the method checks the
# reply for an error member as well as the HTTP status.
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

  [text, result["isError"] == true]
end
# --8<-- [end:config]

# --8<-- [start:select]
# Runs a SELECT with query_database, and prints the column names and each
# row. The reply repeats the query, with the LIMIT that the server adds,
# and then has a line such as "Results (3 rows):", a header line, and one
# line for each row, with the values separated by tabs. The server writes a
# tab or a newline inside a value as \t or \n, and a NULL as an empty
# string.
def select_cheap_products(http)
  text, failed = call_tool(http, "query_database", {
                             query: "SELECT name, price FROM cookbook_mcp.products " \
                                    "WHERE price < 100 ORDER BY price"
                           })
  raise McpError, "query_database failed: #{text}" if failed

  lines = text.split("\n")
  start = lines.index { |line| line.start_with?("Results ") }
  raise McpError, "Unexpected reply: #{text[0, 200]}" if start.nil? || start + 1 >= lines.length

  puts "Columns: #{lines[start + 1].gsub("\t", ", ")}"
  lines[(start + 2)..].reject(&:empty?).each do |line|
    puts "Row: #{line.gsub("\t", ", ")}"
  end
end
# --8<-- [end:select]

# --8<-- [start:insert]
# Tries to add a row. query_database runs every query in a read-only
# transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
# 25006, and the tool returns the error with isError set to true. The
# INSERT leaves out id, which the table requires, so that even a server
# that allows writes would refuse it rather than save a row. That is
# why the method checks for the read-only error itself rather than
# for any error, and fails if the write succeeds or fails for another
# reason. It prints only the last line of the error, which holds
# PostgreSQL's message, because some errors start with the query.
def try_insert(http)
  text, failed = call_tool(http, "query_database", {
                             query: "INSERT INTO cookbook_mcp.products " \
                                    "(name, category, price, in_stock, description) " \
                                    "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " \
                                    "'A made-up product that is never saved')"
                           })
  error_line = text.strip.split("\n").last.to_s
  raise McpError, "The server accepted a write" unless failed
  unless text.include?("SQLSTATE 25006")
    raise McpError, "The INSERT failed for another reason: #{error_line}"
  end

  puts "INSERT rejected: #{error_line}"
end
# --8<-- [end:insert]

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
    select_cheap_products(http)
    try_insert(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "MCP Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
