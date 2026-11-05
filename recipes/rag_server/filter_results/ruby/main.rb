# Ellie's Postgres Cookbook
# Filtering the documents that the pgEdge RAG Server retrieves, using
# Net::HTTP.
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
PIPELINE = env_or("RAG_PIPELINE", "cookbook")

QUESTION = "How long does the Acme Widget take to charge?"

# The product to search, and the versions to ask about in turn. The
# question names no version, so only the filter tells the pipeline which
# documents to use.
PRODUCT = "Acme Widget"
VERSIONS = ["1.0", "2.0"].freeze

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300
# --8<-- [end:config]

# --8<-- [start:filter]
# Returns the filter for a product and a version. The conditions are
# joined with AND, which is the default, and each one compares a column of
# the pipeline's table with a value. The server passes the values to
# PostgreSQL as parameters, so they need no escaping.
def build_filter(product, version)
  {
    logic: "AND",
    conditions: [
      { column: "product", operator: "=", value: product },
      { column: "version", operator: "=", value: version }
    ]
  }
end
# --8<-- [end:filter]

# --8<-- [start:ask]
# Raised when the RAG Server rejects a request or replies oddly.
class RagError < StandardError; end

# Parses text as a JSON object, and returns nil if it is not one.
def parse_object(text)
  value = JSON.parse(text.to_s)
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError
  nil
end

# Describes an error response, which carries a JSON body of the form
# {"error": {"code": "...", "message": "..."}}.
def error_text(response)
  error = parse_object(response.body)&.fetch("error", nil)
  if error.is_a?(Hash) && error["code"].is_a?(String)
    return "#{error["code"]}: #{error["message"]}"
  end

  response.body.to_s.strip[0, 200]
end

# Sends the question and the filter to the pipeline, and asks for the
# documents that the answer came from. Returns the decoded reply.
def ask(http, question, filter)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = JSON.generate({ query: question, filter: filter, include_sources: true })
  response = http.request(request)

  # Net::HTTP treats an error status as a normal response, so check it
  # here.
  unless response.is_a?(Net::HTTPSuccess)
    raise RagError, "HTTP #{response.code}, #{error_text(response)}"
  end

  body = parse_object(response.body)
  unless body && body["answer"].is_a?(String)
    raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
  end

  body
end
# --8<-- [end:ask]

# --8<-- [start:show]
# Prints the answer in a reply, and then the IDs of its sources.
def show(body)
  ids = (body["sources"] || []).map { |source| source.fetch("id", "(no id)").to_s }
  puts "Answer:\n#{body["answer"]}"
  puts "Sources: #{ids.join(", ")}"
end
# --8<-- [end:show]

# --8<-- [start:main]
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) do |http|
    puts "Question: #{QUESTION}"
    VERSIONS.each do |version|
      body = ask(http, QUESTION, build_filter(PRODUCT, version))
      puts
      puts "Filter: product = #{PRODUCT}, version = #{version}"
      show(body)
    end
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
