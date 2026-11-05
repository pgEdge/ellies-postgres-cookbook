# Ellie's Postgres Cookbook
# Chatting with the LLM through the AI DBA Workbench API, using Net::HTTP.
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
  raise "WORKBENCH_TOKEN must be set" unless token

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    token: token
  }
end
# --8<-- [end:config]

# --8<-- [start:request]
# Sends a request to the API and returns the decoded reply. The body, if
# given, is sent as JSON. A request that the server rejects raises an error
# that includes the message from the server.
def api(cfg, method, path, body = nil)
  uri = URI("#{cfg[:base_url]}/api/v1#{path}")
  headers = { "Authorization" => "Bearer #{cfg[:token]}" }
  headers["Content-Type"] = "application/json" if body

  # A small model on a CPU can take a while to answer, so the read timeout
  # is generous.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 300) do |http|
    http.send_request(method, uri.request_uri, body&.to_json, headers)
  end
  if response.code.to_i >= 400
    raise "#{method} #{path} failed with status #{response.code}: " \
          "#{response.body.to_s.strip}"
  end
  JSON.parse(response.body)
end
# --8<-- [end:request]

# --8<-- [start:providers]
# Prints the default provider and model, which the chat endpoint uses when
# a request names neither.
def show_provider(cfg)
  reply = api(cfg, "GET", "/llm/providers")
  default = reply.fetch("providers").find { |p| p["isDefault"] }
  raise "The Workbench has no default LLM provider" if default.nil?

  puts "Provider: #{default.fetch('name')} (model #{reply.fetch('defaultModel')})"
end
# --8<-- [end:providers]

# --8<-- [start:chat]
# Sends a conversation to the model and returns the reply. The messages are
# the conversation so far, each with a role of user or assistant and some
# content.
def chat(cfg, messages)
  api(cfg, "POST", "/llm/chat", { messages: messages })
end

# Returns the text of a reply on a single line. A small model may spread
# its answer over several lines, so the method joins the text blocks and
# collapses the white space. It fails when the reply holds no text.
def reply_text(reply)
  blocks = reply.fetch("content").select { |b| b["type"] == "text" }
  text = blocks.map { |b| b["text"] }.join(" ").split.join(" ")
  raise "The model returned no text" if text.empty?

  text
end
# --8<-- [end:chat]

# --8<-- [start:main]
def main
  cfg = settings
  show_provider(cfg)

  # The first message starts the conversation.
  question = "Name one type of PostgreSQL index, in one sentence."
  messages = [{ role: "user", content: question }]
  text = reply_text(chat(cfg, messages))
  puts "Reply: #{text}"

  # The server keeps no conversation, so the follow-up repeats the earlier
  # messages, including the model's reply, and adds the new question.
  messages += [
    { role: "assistant", content: text },
    { role: "user", content: "Summarise your answer in five words." }
  ]
  follow_up = chat(cfg, messages)
  puts "Follow-up reply: #{reply_text(follow_up)}"
  puts "Stop reason: #{follow_up['stop_reason']}"
  0
# Net::HTTP raises errors of many classes, such as SystemCallError for a
# refused connection and Net::ReadTimeout for a timeout, and the program
# raises RuntimeError for replies that the server rejected or that lacked
# what we need, so this catches StandardError, their common ancestor.
rescue StandardError => e
  warn "Error: #{e.message}"
  1
end

exit main
# --8<-- [end:main]
