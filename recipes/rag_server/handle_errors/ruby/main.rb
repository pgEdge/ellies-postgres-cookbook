# Ellie's Postgres Cookbook
# Handling errors from the pgEdge RAG Server, using Net::HTTP.
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

# A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
MISSING_PIPELINE = "no-such-pipeline"

# The server rejects both requests before it calls a language model, so
# they answer quickly.
TIMEOUT_SECONDS = 30
# --8<-- [end:config]

# --8<-- [start:request]
# Raised when a reply is not one that the program can interpret.
class RagError < StandardError; end

# Raised when the RAG Server replies with an error. The reply has an HTTP
# status and a JSON body of the form
# {"error": {"code": "...", "message": "..."}}.
class ApiError < StandardError
  attr_reader :status, :code, :detail

  def initialize(status, code, detail)
    super("#{code}: #{detail}")
    @status = status
    @code = code
    @detail = detail
  end
end

# Sends a query to a pipeline, and returns the decoded reply. Raises
# ApiError when the server replies with an error.
def send_query(http, pipeline, query)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(pipeline)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = JSON.generate({ query: query })
  response = http.request(request)
  status = response.code.to_i

  begin
    body = JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
  end

  unless response.is_a?(Net::HTTPSuccess)
    error = body.is_a?(Hash) ? body["error"] : nil
    unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
      raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
    end

    raise ApiError.new(status, error["code"], error["message"])
  end

  body
end
# --8<-- [end:request]

# --8<-- [start:advise]
# Returns advice for an error, chosen by the error code. Branch on the code
# rather than on the message, which is meant for people and may change;
# branch on the HTTP status only for the temporary failures that have no
# code worth handling individually.
def advise(err)
  return "Check the pipeline name; GET /v1/pipelines lists the pipelines." if err.code == "PIPELINE_NOT_FOUND"
  return "Fix the request; the body must be JSON with a non-empty query." if err.code == "INVALID_REQUEST"
  return "The failure may be temporary, so retry the request later." if [503, 504].include?(err.status)

  "This program does not handle #{err.code}."
end
# --8<-- [end:advise]

# --8<-- [start:main]
# Sends one query that the server must refuse with the expected error
# code, and prints how the program handles the refusal. Any other outcome
# is a failure.
def demonstrate(http, title, pipeline, query, expected)
  puts title
  begin
    send_query(http, pipeline, query)
  rescue ApiError => e
    puts "  #{e.code} (HTTP #{e.status}): #{e.detail}"
    puts "  #{advise(e)}"
    raise RagError, "expected #{expected}, got #{e.code}" if e.code != expected

    return
  end
  raise RagError, "the request unexpectedly succeeded"
end

begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https", read_timeout: TIMEOUT_SECONDS
  ) do |http|
    demonstrate(http, "Asking a pipeline that does not exist",
                MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
    demonstrate(http, "Asking an empty question",
                PIPELINE, "", "INVALID_REQUEST")
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
