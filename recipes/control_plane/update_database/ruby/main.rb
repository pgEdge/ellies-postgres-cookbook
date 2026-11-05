# Ellie's Postgres Cookbook
# Changing a Postgres setting of a pgEdge Control Plane database, checking
# it from a connection, and putting the original settings back, using
# Net::HTTP and the pg gem.
#
# These examples are for the Control Plane v0.11.0.
#
# The program restores the original settings on every path: after a
# success, after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "pg"
require "uri"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# The password has no default; the Control Plane never returns it, so it
# comes from whoever created the database user.
BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)

TIMEOUT_SECONDS = 30

# The setting to change, and its new value.
SETTING = "work_mem"
VALUE = "16MB"

# How long to wait for an update to finish, and how often to check.
WAIT_SECONDS = 600
POLL_SECONDS = 5

# Raised when the Control Plane rejects a request or replies oddly. The
# status is the HTTP status of the reply, if there was one.
class ControlPlaneError < StandardError
  attr_reader :status

  def initialize(message, status = nil)
    super(message)
    @status = status
  end
end

# The errors that mean no reply arrived: SystemCallError covers a refused
# connection, Timeout::Error covers the connection and read timeouts, and
# SocketError covers an unknown host.
NETWORK_ERRORS = [SystemCallError, Timeout::Error, SocketError, IOError].freeze

# Sends a request to the server, and returns the decoded reply.
def call(method, path, body = nil)
  uri = URI("#{BASE_URL}#{path}")
  request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri)
  if body
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
  end
  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  response = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
  ) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    raise ControlPlaneError.new(
      "HTTP #{response.code}, #{response.body.to_s[0, 200]}", response.code.to_i
    )
  end

  begin
    reply = JSON.parse(response.body.to_s)
    return reply if reply.is_a?(Hash)
  rescue JSON::ParserError
    # The body is not JSON; report it below.
  end
  raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
end
# --8<-- [end:config]

# --8<-- [start:update]
# Sends a whole database spec as an update, and returns the ID of the task
# that applies it. The Control Plane compares the spec with the current
# one and changes only what differs; the work happens in the task after
# the reply.
def update_database(spec)
  reply = call("POST", "/v1/databases/#{DATABASE_ID}", { "spec" => spec })
  reply.dig("task", "task_id") or
    raise ControlPlaneError, "Unexpected response: missing task_id"
end

# Returns a copy of the spec with the setting changed. postgresql_conf
# holds the Postgres settings that the Control Plane manages, and may be
# missing.
def changed_spec(spec)
  spec.merge("postgresql_conf" => (spec["postgresql_conf"] || {}).merge(SETTING => VALUE))
end
# --8<-- [end:update]

# --8<-- [start:wait]
# Polls a task until it finishes, and raises an error unless it completed.
def wait_for_task(task_id)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    status = call("GET", "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}")["status"]
    return if status == "completed"
    if %w[failed canceled].include?(status)
      raise ControlPlaneError, "the task finished with the status #{status}"
    end

    sleep POLL_SECONDS
  end
  raise ControlPlaneError, "the task was still running after #{WAIT_SECONDS} seconds"
end
# --8<-- [end:wait]

# --8<-- [start:connect]
# Connects to the first available instance and returns the current value
# of the setting. Each instance runs one node, and its connection_info
# holds the address and port that clients use.
def show_setting
  database = call("GET", "/v1/databases/#{DATABASE_ID}")
  instance = (database["instances"] || []).find do |i|
    i["state"] == "available" && !Array(i.dig("connection_info", "addresses")).empty?
  end
  raise ControlPlaneError, "no available instance of #{DATABASE_ID}" unless instance

  info = instance["connection_info"]
  conn = PG.connect(
    host: info["addresses"][0], port: info["port"],
    dbname: database.dig("spec", "database_name"),
    user: DATABASE_USER, password: DATABASE_PASSWORD,
    connect_timeout: TIMEOUT_SECONDS
  )
  begin
    conn.exec_params("SELECT current_setting($1)", [SETTING]).getvalue(0, 0)
  ensure
    # Close the connection whether or not the query failed.
    conn.close
  end
end
# --8<-- [end:connect]

# --8<-- [start:restore]
# Sends the original spec back and waits for the task. The Control Plane
# answers 409 whilst another task, such as the update, is still running on
# the database, so the program repeats the request, as it does when no
# reply arrived or the server failed.
def restore(spec)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
  begin
    task_id = update_database(spec)
  rescue ControlPlaneError, *NETWORK_ERRORS => e
    transient = !e.is_a?(ControlPlaneError) ||
                (!e.status.nil? && (e.status == 409 || e.status >= 500))
    raise if !transient || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep POLL_SECONDS
    retry
  end
  wait_for_task(task_id)
end
# --8<-- [end:restore]

# --8<-- [start:main]
if DATABASE_PASSWORD.nil?
  warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
  exit 1
end

exit_code = 0
changed = false
original = nil
begin
  # The spec that the API returns leaves out the passwords of the database
  # users, and an update may leave them out too, which keeps them
  # unchanged.
  original = call("GET", "/v1/databases/#{DATABASE_ID}")["spec"]

  # Restore unless the server refused the request with a 4xx status, which
  # means that it changed nothing.
  puts "Setting #{SETTING} to #{VALUE}"
  changed = true
  begin
    task_id = update_database(changed_spec(original))
  rescue ControlPlaneError => e
    changed = false if e.status && e.status < 500
    raise
  end
  wait_for_task(task_id)
  puts "Update completed"

  puts "#{SETTING} is now #{show_setting}"
rescue ControlPlaneError, *NETWORK_ERRORS => e
  warn "Control Plane error: #{e.message}"
  exit_code = 1
# PG::Error is the base class for the gem's errors, including a failure to
# connect.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit_code = 1
# Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
rescue SignalException
  warn "Interrupted"
  exit_code = 130
ensure
  # Restore the original settings whether the example succeeded, failed,
  # or was interrupted. Ignore further interrupts, so that they cannot cut
  # the cleanup short.
  trap("INT", "IGNORE")
  trap("TERM", "IGNORE")
  if changed
    begin
      restore(original)
      puts "Restored the original settings"
    rescue ControlPlaneError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      warn "Restore the settings of the database #{DATABASE_ID} by hand"
      exit_code = 1
    end
  end
end

exit exit_code
# --8<-- [end:main]
