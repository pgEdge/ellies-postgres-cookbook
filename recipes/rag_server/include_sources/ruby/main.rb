# Ellie's Postgres Cookbook
# Showing the documents behind a pgEdge RAG Server answer, using
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

QUESTION = "How long does the Acme Widget 2.0 take to charge?"

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300
# --8<-- [end:config]

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

# Sends the question to the pipeline, and asks for the documents that the
# answer came from as well. Returns the decoded reply.
def ask(http, question)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = JSON.generate({ query: question, include_sources: true })
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

# --8<-- [start:sources]
# Returns one line for a source: its ID and the start of its text.
def describe_source(source)
  # Collapse any line breaks, and shorten long text for display.
  content = source.fetch("content", "").to_s.split.join(" ")
  content = "#{content[0, 57]}..." if content.length > 60
  "- #{source.fetch("id", "(no id)")}: #{content}"
end

# Prints the sources in a reply, in the order the server returns.
def print_sources(body)
  # The server leaves out the sources array, without an error, when the
  # pipeline does not set allow_include_sources.
  sources = body["sources"]
  if sources.nil? || sources.empty?
    puts "No sources were returned. Does the pipeline set allow_include_sources?"
    return
  end

  puts "Sources (#{sources.length}):"
  sources.each { |source| puts describe_source(source) }
end
# --8<-- [end:sources]

# --8<-- [start:main]
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  body = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) { |http| ask(http, QUESTION) }

  puts "Question: #{QUESTION}"
  puts "Answer:\n#{body["answer"]}"
  print_sources(body)
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
