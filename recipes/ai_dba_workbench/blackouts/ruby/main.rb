# Ellie's Postgres Cookbook
# Scheduling a maintenance blackout with the AI DBA Workbench API, using
# Net::HTTP.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "time"
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
  connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
  raise "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set" unless token && connection_id
  raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A\d+\z/)

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    token: token,
    connection_id: Integer(connection_id, 10)
  }
end
# --8<-- [end:config]

# --8<-- [start:request]
# The name of the signal that the program received, if any.
$interrupted = nil

# Records that the program received SIGINT or SIGTERM. The handler replaces
# the default action, which would end the program before it could delete
# the blackout, and a second signal does nothing more.
def catch_signals
  %w[INT TERM].each do |name|
    Signal.trap(name) { $interrupted = "SIG#{name}" }
  end
end

# Sends a request to the API and returns the decoded reply, or nil if the
# reply has no body. A request that the server rejects raises an error that
# includes the message from the server. After a signal, every request that
# is interruptible fails at once; the cleanup and the create call, whose
# result the program must not lose, pass false.
def api(method, cfg, path, interruptible: true, body: nil)
  raise "Interrupted by #{$interrupted}" if interruptible && $interrupted

  uri = URI("#{cfg[:base_url]}/api/v1#{path}")
  headers = { "Authorization" => "Bearer #{cfg[:token]}" }
  headers["Content-Type"] = "application/json" if body

  # Net::HTTP has no overall timeout, so limit both the connection and
  # each read.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.send_request(method, uri.request_uri, body&.to_json, headers)
  end
  if response.code.to_i >= 400
    raise "#{method} #{path} failed with status #{response.code}: " \
          "#{response.body.to_s.strip}"
  end
  text = response.body.to_s
  text.empty? ? nil : JSON.parse(text)
end
# --8<-- [end:request]

# --8<-- [start:create]
# Creates a blackout for one monitored server and returns it. The blackout
# starts a minute ago, so that a small difference between the clocks of
# this machine and the server cannot leave it inactive, and it ends in one
# hour. The times are in RFC 3339 format.
def create_blackout(cfg)
  now = Time.now.utc
  api("POST", cfg, "/blackouts", interruptible: false, body: {
        scope: "server",
        connection_id: cfg[:connection_id],
        reason: "Cookbook maintenance window",
        start_time: (now - 60).iso8601,
        end_time: (now + 3600).iso8601
      })
end
# --8<-- [end:create]

# --8<-- [start:read]
# Returns the blackout with the given ID.
def get_blackout(cfg, blackout_id)
  api("GET", cfg, "/blackouts/#{blackout_id}")
end
# --8<-- [end:read]

# --8<-- [start:stop]
# Stops a blackout that is in progress, which sets its end time to now, and
# returns the stopped blackout.
def stop_blackout(cfg, blackout_id)
  api("POST", cfg, "/blackouts/#{blackout_id}/stop")
end
# --8<-- [end:stop]

# --8<-- [start:delete]
# Deletes a blackout by its ID.
def delete_blackout(cfg, blackout_id)
  api("DELETE", cfg, "/blackouts/#{blackout_id}", interruptible: false)
end
# --8<-- [end:delete]

# --8<-- [start:main]
def main
  cfg = nil
  blackout_id = nil
  status = 0
  catch_signals
  begin
    cfg = settings

    created = create_blackout(cfg)
    blackout_id = created.fetch("id")
    puts "Created a blackout for the server (active: #{created.fetch('is_active')})"

    blackout = get_blackout(cfg, blackout_id)
    puts "Read the blackout back (active: #{blackout.fetch('is_active')})"

    stopped = stop_blackout(cfg, blackout_id)
    puts "Stopped the blackout (active: #{stopped.fetch('is_active')})"
    raise "The blackout is still active" if stopped["is_active"]

    delete_blackout(cfg, blackout_id)
    blackout_id = nil
    puts "Deleted the blackout"
  # Net::HTTP raises errors of many classes, such as SystemCallError for a
  # refused connection and Net::OpenTimeout for a timeout, and the program
  # raises RuntimeError for replies that the server rejected or that lacked
  # what we need, so this catches StandardError, their common ancestor.
  rescue StandardError => e
    warn "Error: #{e.message}"
    status = 1
  ensure
    # Delete the blackout whether or not a later step failed, so that a
    # failed run does not leave alerts suppressed.
    if blackout_id
      begin
        delete_blackout(cfg, blackout_id)
      rescue StandardError => e
        warn "Error: could not delete the blackout: #{e.message}"
        status = 1
      end
    end
  end
  status
end

exit main
# --8<-- [end:main]
