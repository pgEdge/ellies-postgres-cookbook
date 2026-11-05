# Ellie's Postgres Cookbook
# Exploring a schema through the pgEdge Postgres MCP Server, using
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

# The schema and table that scripts/start_postgres_mcp.sh creates.
SCHEMA = "cookbook_mcp"
TABLE = "products"

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

# --8<-- [start:parse_tsv]
# Reads the table in a tool's reply into a list of rows, each a hash keyed
# by column name. The reply starts with a line or two about the database,
# and then has a header line and one line for each row, with the values
# separated by tabs. The server writes a tab or a newline inside a value as
# \t or \n, so splitting on them is safe. The header is the first line that
# starts with "schema", the first column of every table that
# get_schema_info returns.
def parse_tsv(text)
  lines = text.split("\n")
  start = lines.index { |line| line.start_with?("schema\t") }
  raise McpError, "The reply had no table: #{text[0, 200]}" if start.nil?

  # A limit of -1 keeps empty strings at the end, such as an empty last
  # column.
  header = lines[start].split("\t", -1)
  lines[(start + 1)..].reject(&:empty?).map do |line|
    header.zip(line.split("\t", -1)).to_h
  end
end
# --8<-- [end:parse_tsv]

# --8<-- [start:list_tables]
# Lists the tables in the schema with their comments. With compact set to
# true, get_schema_info returns one line for each table, without its
# columns, which suits a first look at a large database.
def list_tables(http)
  text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, compact: true })
  puts "Tables in #{SCHEMA}:"
  parse_tsv(text).each do |row|
    comment = row["table_desc"].to_s
    puts "- #{row["table"]}: #{comment.empty? ? "(no comment)" : comment}"
  end
end
# --8<-- [end:list_tables]

# --8<-- [start:describe_table]
# Lists the columns of one table with their types. Given a table_name,
# get_schema_info returns one line for each column, which also carries the
# table's details.
def describe_table(http)
  text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, table_name: TABLE })
  rows = parse_tsv(text)
  raise McpError, "#{SCHEMA}.#{TABLE} has no columns" if rows.empty?

  puts "Columns of #{SCHEMA}.#{TABLE}:"
  rows.each do |row|
    key = row["is_pk"] == "true" ? " (primary key)" : ""
    puts "- #{row["column"]}: #{row["data_type"]}#{key}"
  end
end
# --8<-- [end:describe_table]

# --8<-- [start:count_rows]
# Counts the products in stock with count_rows. The where argument is a
# condition without the WHERE keyword; the server rejects one that
# contains a subquery.
def count_in_stock(http)
  text = call_tool(http, "count_rows", { schema: SCHEMA, table: TABLE, where: "in_stock" })
  # The reply ends with a line such as "Count: 4".
  match = text.match(/^Count: (\d+)$/)
  raise McpError, "The reply had no count: #{text[0, 200]}" if match.nil?

  puts "Products in stock: #{match[1]}"
end
# --8<-- [end:count_rows]

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
    list_tables(http)
    describe_table(http)
    count_in_stock(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "MCP Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
