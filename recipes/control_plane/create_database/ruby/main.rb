# Ellie's Postgres Cookbook
# Creating a pgEdge Control Plane database on one host, waiting until it is
# available, and deleting it again, using Net::HTTP.
#
# These examples are for the Control Plane v0.11.0.
#
# The database runs in containers on the host until it is deleted, so this
# program deletes the database it creates on every path: after a success,
# after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "securerandom"
require "uri"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# The new database listens on the given port on its host, so choose one
# that is free.
BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
PORT_TEXT = env_or("CONTROL_PLANE_RECIPE_PORT", "6433")

TIMEOUT_SECONDS = 30

# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
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

# --8<-- [start:host]
# Returns the ID of the first host in the cluster. A database places each
# of its nodes on one or more hosts, which run the Postgres containers.
def first_host
  host = (call("GET", "/v1/hosts")["hosts"] || []).first
  raise ControlPlaneError, "the cluster has no hosts" unless host

  host["id"]
end
# --8<-- [end:host]

# --8<-- [start:create]
# Asks the Control Plane to create a database with one node. The reply
# holds the database and the task that creates it; the work happens in the
# background after the reply.
def create_database(database_id, host)
  call("POST", "/v1/databases", {
         id: database_id,
         spec: {
           database_name: "recipe",
           port: Integer(PORT_TEXT, 10),
           nodes: [{ name: "n1", host_ids: [host] }]
         }
       })
end
# --8<-- [end:create]

# --8<-- [start:wait]
# Polls the database, printing its state each time it changes, until the
# state is available, and returns the port of its first instance. Each
# instance runs one node, and its connection_info holds the address and
# port that clients use. A failed state ends the wait at once.
def wait_until_available(database_id)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
  last = nil
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    database = call("GET", "/v1/databases/#{database_id}")
    state = database["state"]
    if state != last
      puts "Database state: #{state}"
      last = state
    end
    if state == "available"
      instance = (database["instances"] || []).first
      raise ControlPlaneError, "the database is available but has no instances" unless instance

      return instance.fetch("connection_info").fetch("port")
    end
    raise ControlPlaneError, "the database has the state failed" if state == "failed"

    sleep POLL_SECONDS
  end
  raise ControlPlaneError, "the database was not available after #{WAIT_SECONDS} seconds"
end
# --8<-- [end:wait]

# --8<-- [start:delete]
# Reports whether a failed request is worth repeating: no reply arrived,
# the server failed, or it answered 409, which the Control Plane does
# whilst another task, such as the create, is still running on the
# database.
def transient?(error)
  return true unless error.is_a?(ControlPlaneError)

  !error.status.nil? && (error.status == 409 || error.status >= 500)
end

# Deletes the database and waits until the API no longer has it. A 404
# means that the database is already gone.
def delete_database(database_id)
  path = "/v1/databases/#{database_id}"
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
  begin
    task_id = call("DELETE", path).fetch("task").fetch("task_id")
  rescue ControlPlaneError, *NETWORK_ERRORS => e
    return if e.is_a?(ControlPlaneError) && e.status == 404
    raise if !transient?(e) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep POLL_SECONDS
    retry
  end

  # The delete starts a task that removes the database; a 404 shows that
  # it has finished. Whilst the database is still there, the status of the
  # task shows whether the delete failed.
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    begin
      call("GET", path)
      status = call("GET", "#{path}/tasks/#{task_id}")["status"]
      if %w[failed canceled].include?(status)
        raise ControlPlaneError, "the delete task finished with the status #{status}"
      end
    rescue ControlPlaneError, *NETWORK_ERRORS => e
      return if e.is_a?(ControlPlaneError) && e.status == 404
      raise unless transient?(e)
    end
    sleep POLL_SECONDS
  end
  raise ControlPlaneError, "the database was still present after #{WAIT_SECONDS} seconds"
end
# --8<-- [end:delete]

# --8<-- [start:main]
# The new database listens on this port, so check it before creating
# anything.
unless PORT_TEXT.match?(/\A[1-9][0-9]{0,4}\z/) && Integer(PORT_TEXT, 10) <= 65_535
  warn "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535"
  exit 1
end

exit_code = 0
created = false
# The client chooses the ID of a new database, so the program knows it
# before the request, and can delete the database even if the reply never
# arrives. The random suffix keeps the ID unique.
database_id = "cookbook-recipe-#{SecureRandom.hex(3)}"
begin
  host = first_host
  puts "Host: #{host}"

  # Clean up unless the server refused the request with a 4xx status,
  # which means it created nothing; a 409, for example, means that a
  # database with this ID already exists, and is not this program's to
  # delete.
  created = true
  begin
    create_database(database_id, host)
  rescue ControlPlaneError => e
    created = false if e.status&.between?(400, 499)
    raise
  end
  puts "Created database #{database_id}"

  port = wait_until_available(database_id)
  puts "Database is available on port #{port}"
rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
  warn "Control Plane error: #{e.message}"
  exit_code = 1
# Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
rescue SignalException
  warn "Interrupted"
  exit_code = 130
ensure
  # Delete the database whether the example succeeded, failed, or was
  # interrupted. Ignore further interrupts, so that they cannot cut the
  # cleanup short.
  trap("INT", "IGNORE")
  trap("TERM", "IGNORE")
  if created
    begin
      delete_database(database_id)
      puts "Deleted database"
    rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      warn "Delete the database #{database_id} by hand"
      exit_code = 1
    end
  end
end

exit exit_code
# --8<-- [end:main]
