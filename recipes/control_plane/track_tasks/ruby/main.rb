# Ellie's Postgres Cookbook
# Finding the task that created a pgEdge Control Plane database, and
# following its log until the task finishes, using Net::HTTP.
#
# These examples are for the Control Plane v0.11.0.
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

BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")

TIMEOUT_SECONDS = 30

# How long to follow a task that is still running, and how often to check.
FOLLOW_SECONDS = 600
POLL_SECONDS = 5

# The statuses after which a task does not change again.
FINAL_STATUSES = %w[completed failed canceled].freeze

# Raised when the Control Plane rejects a request or replies oddly.
class ControlPlaneError < StandardError; end

# Fetches a path from the server, and returns the decoded reply. The query
# hash is encoded and added to the URL.
def get(http, path, query = {})
  uri = URI("#{BASE_URL}#{path}")
  uri.query = URI.encode_www_form(query) unless query.empty?
  response = http.request(Net::HTTP::Get.new(uri))
  unless response.is_a?(Net::HTTPSuccess)
    raise ControlPlaneError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
  end

  begin
    body = JSON.parse(response.body.to_s)
    return body if body.is_a?(Hash)
  rescue JSON::ParserError
    # The body is not JSON; report it below.
  end
  raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
end
# --8<-- [end:config]

# --8<-- [start:list]
# Returns the ID of the task that created the database. Every create,
# update and delete runs as a task. The IDs sort by creation time, and
# sort_order=asc lists the oldest task first.
def find_create_task(http)
  reply = get(http, "/v1/databases/#{DATABASE_ID}/tasks", { "sort_order" => "asc" })
  task = (reply["tasks"] || []).find { |t| t["type"] == "create" }
  raise ControlPlaneError, "no create task for #{DATABASE_ID}" unless task

  task["task_id"]
end
# --8<-- [end:list]

# --8<-- [start:follow]
# Prints the log of a task as it grows, until the task finishes, and
# returns its final status. Each log reply carries last_entry_id, and
# passing that back as after_entry_id fetches only the newer entries. The
# status is read before the log, so that once it is final, the log that
# follows it is complete.
def follow_task(http, task_id)
  path = "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}"
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FOLLOW_SECONDS
  after = nil
  loop do
    status = get(http, path)["status"] || "unknown"

    log = get(http, "#{path}/log", after ? { "after_entry_id" => after } : {})
    (log["entries"] || []).each { |entry| puts "Log: #{entry["message"]}" }
    after = log["last_entry_id"] unless log["last_entry_id"].to_s.empty?

    return status if FINAL_STATUSES.include?(status)
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      raise ControlPlaneError, "task #{task_id} was still #{status} after #{FOLLOW_SECONDS} seconds"
    end

    sleep POLL_SECONDS
  end
end
# --8<-- [end:follow]

# --8<-- [start:main]
begin
  uri = URI(BASE_URL)
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  status = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) do |http|
    task_id = find_create_task(http)
    puts "Task: create"
    follow_task(http, task_id)
  end
# SystemCallError covers a refused connection, Timeout::Error covers the
# connection and read timeouts, and SocketError covers an unknown host.
rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
  warn "Control Plane error: #{e.message}"
  exit 1
end

puts "Status: #{status}"
exit 1 unless status == "completed"
# --8<-- [end:main]
