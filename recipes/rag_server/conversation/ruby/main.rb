# Ellie's Postgres Cookbook
# Holding a conversation with the pgEdge RAG Server, using Net::HTTP.
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

# The second question does not say which version of the Acme Widget it
# means, so only the first question and its answer, which the model
# receives as history, settle that. The search uses only the current
# question, which is why this one still names the product.
QUESTIONS = [
  "How long does the Acme Widget 2.0 take to charge?",
  "And how many hours does the Acme Widget run for once it is charged?"
].freeze

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

# Sends a question and the conversation so far to the pipeline, and
# returns the answer. The server keeps no conversation between requests,
# so history lists the earlier messages, each with a role of user or
# assistant, in order.
def ask(http, question, history)
  uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = JSON.generate({ query: question, messages: history })
  response = http.request(request)

  # Net::HTTP treats an error status as a normal response, so check it
  # here.
  unless response.is_a?(Net::HTTPSuccess)
    raise RagError, "HTTP #{response.code}, #{error_text(response)}"
  end

  answer = parse_object(response.body)&.fetch("answer", nil)
  unless answer.is_a?(String)
    raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
  end

  answer
end
# --8<-- [end:ask]

# --8<-- [start:converse]
# Asks each question in turn, printing both sides of the conversation.
# After each answer, the question and the answer join the history that
# the next request carries.
def converse(http)
  history = []
  QUESTIONS.each do |question|
    answer = ask(http, question, history)
    puts "You: #{question}"
    puts "Assistant: #{answer}"
    history << { role: "user", content: question }
    history << { role: "assistant", content: answer }
  end
end
# --8<-- [end:converse]

# --8<-- [start:main]
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) { |http| converse(http) }
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "RAG Server error: #{e.message}"
  exit 1
end
# --8<-- [end:main]
