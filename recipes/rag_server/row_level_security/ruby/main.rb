# Ellie's Postgres Cookbook
# Answering each caller from only their own documents with the pgEdge RAG
# Server and row-level security, using Net::HTTP.
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
PIPELINE = env_or("RAG_PIPELINE", "cookbook_private")

QUESTION = "What is the status of my warranty claim?"

# The callers to ask for. The fictional documents in the pipeline's table
# belong to these two people.
CALLERS = ["jane.doe@example.com", "john.smith@example.com"].freeze

# The header in which the server expects a trusted proxy to put the claims
# of the caller. This is the server's default; the identity.claims_header
# setting changes it.
CLAIMS_HEADER = "X-Forwarded-Claims"

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300
# --8<-- [end:config]

# --8<-- [start:ask]
# Raised when a reply is not one that the program can interpret.
class RagError < StandardError; end

# Raised when the RAG Server replies with an error. The reply has an HTTP
# status and a JSON body of the form
# {"error": {"code": "...", "message": "..."}}.
class ApiError < StandardError
  attr_reader :status, :code

  def initialize(status, code, detail)
    super("#{code}: #{detail}")
    @status = status
    @code = code
  end
end

# Parses text as a JSON object, and returns nil if it is not one.
def parse_object(text)
  value = JSON.parse(text.to_s)
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError
  nil
end

# Sends the question to the pipeline on behalf of a caller, and asks for
# the documents that the answer came from. Returns the decoded reply. A
# subject of nil sends no identity at all.
def ask(http, subject)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  # The claims are a JSON object, which JSON.generate builds, so that the
  # subject needs no escaping.
  request[CLAIMS_HEADER] = JSON.generate({ sub: subject }) unless subject.nil?
  request.body = JSON.generate({ query: QUESTION, include_sources: true })
  response = http.request(request)
  body = parse_object(response.body)

  unless response.is_a?(Net::HTTPSuccess)
    error = body&.fetch("error", nil)
    unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
      raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
    end

    raise ApiError.new(response.code.to_i, error["code"], error["message"])
  end

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
# Asks the question without an identity. The server must refuse with
# IDENTITY_REQUIRED, because it never falls back to the pipeline's own
# database role; any other outcome is a failure.
def ask_anonymously(http)
  puts
  puts "Caller: (no identity)"
  begin
    ask(http, nil)
  rescue ApiError => e
    puts "#{e.code} (HTTP #{e.status})"
    raise RagError, "expected IDENTITY_REQUIRED, got #{e.message}" if e.code != "IDENTITY_REQUIRED"

    return
  end
  raise RagError, "the server answered without an identity; is identity.enabled set?"
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
    puts "Question: #{QUESTION}"
    CALLERS.each do |caller|
      body = ask(http, caller)
      puts
      puts "Caller: #{caller}"
      show(body)
    end
    ask_anonymously(http)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue ApiError, RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
