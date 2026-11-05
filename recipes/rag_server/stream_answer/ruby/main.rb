# Ellie's Postgres Cookbook
# Streaming an answer from the pgEdge RAG Server, using Net::HTTP.
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

# The timeout applies to each wait for data rather than to the whole
# stream, but the server may wait for the language model to begin, and a
# small model on a modest machine can take a while, so allow plenty of
# time.
TIMEOUT_SECONDS = 300
# --8<-- [end:config]

# --8<-- [start:events]
# Yields each line of a response body, without its line ending, as soon as
# the whole line has arrived. read_body hands over the body in pieces that
# need not end at a line break, so the start of a line waits in a buffer
# for the rest.
def each_line(response)
  buffer = String.new
  response.read_body do |piece|
    buffer << piece
    while (index = buffer.index("\n"))
      yield buffer.slice!(0..index).chomp.force_encoding(Encoding::UTF_8)
    end
  end
  yield buffer.chomp.force_encoding(Encoding::UTF_8) unless buffer.empty?
end

# Parses Server-Sent Events from a response, and yields the JSON that the
# data of each event holds, as each event arrives.
#
# An event is one or more "data:" lines followed by a blank line. The
# stream may end without the final blank line, so the last event is sent
# when the lines run out as well. JSON.parse raises JSON::ParserError for
# data that is not valid JSON.
def read_events(response)
  data = []
  each_line(response) do |line|
    if line.empty?
      yield JSON.parse(data.join("\n")) unless data.empty?
      data = []
    elsif line.start_with?("data:")
      # A single space after the colon is not part of the data.
      data << line.delete_prefix("data:").delete_prefix(" ")
    end
    # Comment lines (which start with a colon) and other fields are
    # ignored.
  end
  yield JSON.parse(data.join("\n")) unless data.empty?
end
# --8<-- [end:events]

# --8<-- [start:stream]
# Raised when the RAG Server rejects a request or the stream fails.
class RagError < StandardError; end

# Describes an error response, which carries a JSON body of the form
# {"error": {"code": "...", "message": "..."}}.
def error_text(body)
  error = JSON.parse(body.to_s)["error"]
  return "#{error["code"]}: #{error["message"]}" if error.is_a?(Hash) && error["code"].is_a?(String)

  body.to_s.strip[0, 200]
rescue JSON::ParserError, NoMethodError, TypeError
  body.to_s.strip[0, 200]
end

# Prints the answer as it arrives, and returns the number of chunks.
def stream_answer(http, question)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = JSON.generate({ query: question, stream: true })

  chunks = 0
  error = nil
  done = false

  # Given a block, request hands over the response before reading its
  # body, which the block then reads as the server sends it.
  http.request(request) do |response|
    # A request the server rejects gets an ordinary error status. Once
    # streaming starts the status is always 200, so later failures arrive
    # as events instead.
    unless response.is_a?(Net::HTTPSuccess)
      raise RagError, "HTTP #{response.code}, #{error_text(response.read_body)}"
    end

    read_events(response) do |event|
      # Anything other than a JSON object is not an event this program
      # knows, so skip it.
      next unless event.is_a?(Hash)

      case event["type"]
      when "chunk"
        # The last chunk has no content.
        content = event["content"].to_s
        unless content.empty?
          # Ruby buffers standard output when it is not a terminal, so
          # flush it to show each chunk at once.
          print content
          $stdout.flush
          chunks += 1
        end
      when "error"
        message = event["error"].to_s
        error = message.empty? ? "unknown error" : message
      when "done"
        done = true
      end
    end
  end

  puts
  # The server sends a done event after an error event, so keep reading
  # until the stream ends before reporting the error.
  raise RagError, "The stream reported an error: #{error}" if error
  raise RagError, "The stream ended before the done event" unless done

  chunks
end
# --8<-- [end:stream]

# --8<-- [start:main]
puts "Question: #{QUESTION}"
puts "Answer:"
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  chunks = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) { |http| stream_answer(http, QUESTION) }
  puts "Chunks received: #{chunks}"
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, SocketError covers an unknown host, and
# JSON::ParserError covers an event whose data is not valid JSON.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError,
       JSON::ParserError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
