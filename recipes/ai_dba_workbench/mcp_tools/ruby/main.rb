# Ellie's Postgres Cookbook
# Calling AI DBA Workbench MCP tools, using Net::HTTP.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty, as an unset variable would be.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# Reads the settings from the environment.
def settings
  token = env_or("WORKBENCH_TOKEN", nil)
  connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
  raise "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set" unless token && connection_id
  raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A[0-9]+\z/)

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    token: token,
    connection_id: connection_id.to_i
  }
end
# --8<-- [end:config]

# --8<-- [start:rpc]
# Sends a JSON-RPC request to the MCP endpoint and returns the result. The
# server answers a JSON-RPC error with HTTP status 200, so the method
# checks the reply for an error member as well as for an HTTP failure.
def rpc(cfg, method, params)
  uri = URI("#{cfg[:base_url]}/mcp/v1")
  headers = {
    "Authorization" => "Bearer #{cfg[:token]}",
    "Content-Type" => "application/json"
  }
  body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json

  # Net::HTTP has no overall timeout, so limit both the connection and
  # each read.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.post(uri.request_uri, body, headers)
  end
  if response.code.to_i >= 400
    raise "#{method} failed with status #{response.code}: " \
          "#{response.body.to_s.strip}"
  end
  reply = JSON.parse(response.body)
  raise "#{method} failed: #{reply['error']['message']}" if reply.key?("error")

  reply.fetch("result")
end
# --8<-- [end:rpc]

# --8<-- [start:initialize]
# Introduces the client to the server and prints the server's name and
# version. The Workbench keeps no session, so a client can skip this step.
# Ruby uses the name initialize for constructors, so the method has another.
def initialize_session(cfg)
  result = rpc(cfg, "initialize", {
                 protocolVersion: "2024-11-05",
                 capabilities: {},
                 clientInfo: { name: "cookbook", version: "1.0.0" }
               })
  info = result.fetch("serverInfo")
  puts "Server: #{info.fetch('name')} #{info.fetch('version')}"
end
# --8<-- [end:initialize]

# --8<-- [start:list_tools]
# Lists the tools, checks that the two that the program calls are present,
# and prints the arguments that each one requires.
def list_tools(cfg)
  tools = rpc(cfg, "tools/list", {}).fetch("tools").to_h { |t| [t["name"], t] }
  # The server lists its tools in no fixed order, so look the two tools up
  # by name.
  %w[query_database execute_explain].each do |name|
    raise "The server does not offer #{name}" unless tools.key?(name)

    required = tools[name].fetch("inputSchema").fetch("required").join(", ")
    puts "#{name} requires: #{required}"
  end
end
# --8<-- [end:list_tools]

# --8<-- [start:call_tool]
# Calls a tool and returns the text of its reply. A tool that fails returns
# a normal result with isError set, so the method checks that flag too.
def call_tool(cfg, name, arguments)
  result = rpc(cfg, "tools/call", { name: name, arguments: arguments })
  text = result.fetch("content").fetch(0).fetch("text")
  raise "#{name} failed: #{text}" if result["isError"]

  text
end
# --8<-- [end:call_tool]

# --8<-- [start:query_database]
# Runs a harmless read-only query with query_database and prints the column
# names and the rows. The reply is text that starts with the connection and
# the query, and then has a "Results" line followed by the rows in
# tab-separated form, so the method prints only what follows that line.
def query_database(cfg)
  text = call_tool(cfg, "query_database", {
                     connection_id: cfg[:connection_id],
                     query: "SELECT 'Hello from the Workbench' AS greeting, " \
                            "6 * 7 AS answer"
                   })
  _, found, results = text.partition("\nResults")
  raise "The reply had no results" if found.empty?

  # Skip the rest of the Results line, then turn the tabs into commas.
  lines = results.split("\n", -1).drop(1).reject(&:empty?)
  lines.each_with_index do |line, number|
    label = number.zero? ? "Columns" : "Row"
    puts "#{label}: #{line.split("\t", -1).join(', ')}"
  end
end
# --8<-- [end:query_database]

# --8<-- [start:execute_explain]
# Plans a query with execute_explain, without running it, and prints the
# type of the first node of the plan. Setting analyze to true would run the
# query.
def execute_explain(cfg)
  text = call_tool(cfg, "execute_explain", {
                     connection_id: cfg[:connection_id],
                     query: "SELECT 1 + 1",
                     analyze: false
                   })
  # The plan follows a line of equals signs.
  match = /Execution Plan:\n=+\n(\S+)/.match(text)
  raise "The reply had no execution plan" unless match

  puts "Plan starts with: #{match[1]}"
end
# --8<-- [end:execute_explain]

# --8<-- [start:main]
def main
  cfg = settings
  initialize_session(cfg)
  list_tools(cfg)
  query_database(cfg)
  execute_explain(cfg)
  0
# Net::HTTP raises errors of many classes, such as SystemCallError for a
# refused connection and Net::OpenTimeout for a timeout, and the program
# raises RuntimeError for replies that the server rejected or that lacked
# what we need, so this catches StandardError, their common ancestor.
rescue StandardError => e
  warn "Error: #{e.message}"
  1
end

exit main
# --8<-- [end:main]
