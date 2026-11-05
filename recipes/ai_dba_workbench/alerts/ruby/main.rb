# Ellie's Postgres Cookbook
# Listing and acknowledging alerts with the AI DBA Workbench API, using
# Net::HTTP.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
# --8<-- [end:imports]

# --8<-- [start:config]
# The rule that the program makes fire. The metric_staleness rule alerts
# when a probe's data is out of date, and the alerter checks it every
# minute.
RULE_NAME = "metric_staleness"

# The longest the whole run waits for alerts, in seconds. The alerter
# evaluates its rules once a minute and clears an alert up to 30 seconds
# after it fires, so this allows for waiting out the alert from an earlier
# run, one alert that clears before the program can acknowledge it, and a
# second evaluation.
WAIT_SECONDS = 150

# How often the program polls the alerts, in seconds.
POLL_SECONDS = 0.5

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

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    token: token,
    connection_id: connection_id
  }
end
# --8<-- [end:config]

# --8<-- [start:request]
# Sends a request to the API and returns the decoded reply, or nil if the
# reply has no body. The query parameters and the body are optional. A
# request that the server rejects raises an error that includes the
# message from the server.
def api(method, cfg, path, params: nil, body: nil)
  uri = URI("#{cfg[:base_url]}/api/v1#{path}")
  uri.query = URI.encode_www_form(params) if params
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

# --8<-- [start:find_rule]
# Returns the ID of an alert rule, given its name.
def find_rule(cfg, name)
  rule = api("GET", cfg, "/alert-rules").find { |r| r["name"] == name }
  raise "There is no alert rule named '#{name}'" if rule.nil?

  rule.fetch("id")
end
# --8<-- [end:find_rule]

# --8<-- [start:set_override]
# Overrides the threshold of a rule for one server. A threshold of -1 is
# below any value that the staleness ratio can take, so the rule is
# violated on the next evaluation.
def set_override(cfg, rule_id)
  api("PUT", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}",
      body: { operator: ">", threshold: -1, severity: "info", enabled: true })
end
# --8<-- [end:set_override]

# --8<-- [start:wait_for_alert]
# Returns the threshold alerts for the server that have the given status.
# The request asks for the most alerts that the API returns at once, so
# that the result does not depend on the first 100 alerts of a busy
# Workbench.
def list_alerts(cfg, status)
  api("GET", cfg, "/alerts", params: {
        connection_id: cfg[:connection_id], status: status,
        alert_type: "threshold", limit: 1000
      }).fetch("alerts")
end

# Returns the active alerts that the given rule raised for the server.
def active_alerts(cfg, rule_id)
  list_alerts(cfg, "active").select { |alert| alert["rule_id"] == rule_id }
end

# Returns the seconds on a clock that only moves forwards, for deadlines.
def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# Waits until the rule has no active alert. The alerter raises no new alert
# for a rule while one is active, so an alert left by an earlier run, which
# clears within 30 seconds, would otherwise stand in for the one that this
# run causes.
def wait_until_quiet(cfg, rule_id, deadline)
  until active_alerts(cfg, rule_id).empty?
    raise "An earlier alert did not clear in time" if now >= deadline

    sleep POLL_SECONDS
  end
end

# Polls until the given rule raises an alert, and returns it. The alert
# clears itself within 30 seconds of firing, so the program polls twice a
# second.
def wait_for_alert(cfg, rule_id, deadline)
  loop do
    alert = active_alerts(cfg, rule_id).first
    return alert if alert
    raise "No alert was raised within #{WAIT_SECONDS} seconds" if now >= deadline

    sleep POLL_SECONDS
  end
end
# --8<-- [end:wait_for_alert]

# --8<-- [start:acknowledge]
# Acknowledges an alert, with a message that the interface shows.
def acknowledge_alert(cfg, alert_id)
  api("POST", cfg, "/alerts/acknowledge",
      body: { alert_id: alert_id, message: "Acknowledged by the cookbook" })
end
# --8<-- [end:acknowledge]

# --8<-- [start:check]
# Returns the status of an alert, found by its ID in the list of
# acknowledged alerts.
def alert_status(cfg, alert_id)
  alert = list_alerts(cfg, "acknowledged").find { |a| a["id"] == alert_id }
  raise "The alert is missing from the acknowledged alerts" if alert.nil?

  alert.fetch("status")
end
# --8<-- [end:check]

# --8<-- [start:unacknowledge]
# Returns an acknowledged alert to the active state. The alerter clears
# only active alerts, so an alert that stays acknowledged also stops the
# rule from raising a new one.
def unacknowledge_alert(cfg, alert_id)
  api("DELETE", cfg, "/alerts/acknowledge", params: { alert_id: alert_id })
end
# --8<-- [end:unacknowledge]

# --8<-- [start:remove_override]
# Removes the override, so that the rule reverts to its default threshold.
def remove_override(cfg, rule_id)
  api("DELETE", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}")
end
# --8<-- [end:remove_override]

# --8<-- [start:main]
# Reports whether a list of alerts includes the one with an ID.
def includes_alert?(alerts, alert_id)
  alerts.any? { |a| a["id"] == alert_id }
end

def main
  cfg = nil
  override_rule = nil
  acknowledged_alert = nil
  status = 0
  begin
    cfg = settings
    deadline = now + WAIT_SECONDS

    rule_id = find_rule(cfg, RULE_NAME)
    puts "Found the rule '#{RULE_NAME}'"

    # An alert from an earlier run may still be active.
    wait_until_quiet(cfg, rule_id, deadline)

    # Record the override first and remove it in the ensure block, so that
    # a failed run does not leave the server raising alerts.
    override_rule = rule_id
    set_override(cfg, rule_id)
    puts "Set an override that makes the rule fire"

    puts "Waiting for the alerter to raise an alert"
    alert = nil
    loop do
      alert = wait_for_alert(cfg, rule_id, deadline)

      # Record the alert before acknowledging it, so that the ensure block
      # returns it to the active state even if the request times out after
      # the server has acted on it.
      acknowledged_alert = alert["id"]
      begin
        acknowledge_alert(cfg, alert["id"])
        break
      rescue StandardError
        # The alerter may have cleared the alert since the poll. The
        # override is still in place, so the rule fires again at the next
        # evaluation; any other failure is real.
        if includes_alert?(active_alerts(cfg, rule_id), alert["id"])
          # The server did not acknowledge it, so there is nothing to undo.
          acknowledged_alert = nil
          raise
        end
        # If the server acted on a request that timed out, the alert is
        # acknowledged and must go back to active. When that fails, the
        # error propagates and the ensure block tries again, because
        # acknowledged_alert is still set.
        if includes_alert?(list_alerts(cfg, "acknowledged"), alert["id"])
          unacknowledge_alert(cfg, alert["id"])
        end
        acknowledged_alert = nil
        warn "The alert cleared first; waiting for the next one"
      end
    end
    puts "An alert is active (severity: #{alert.fetch('severity')})"
    puts "Acknowledged the alert"

    puts "The alert is now #{alert_status(cfg, alert['id'])}"

    unacknowledge_alert(cfg, alert["id"])
    acknowledged_alert = nil
    puts "Returned the alert to the active state"

    remove_override(cfg, rule_id)
    override_rule = nil
    puts "Removed the override"
  # Net::HTTP raises errors of many classes, such as SystemCallError for a
  # refused connection and Net::OpenTimeout for a timeout, and the program
  # raises RuntimeError for replies that the server rejected or that lacked
  # what we need, so this catches StandardError, their common ancestor.
  rescue StandardError => e
    warn "Error: #{e.message}"
    status = 1
  ensure
    # Undo the changes whether or not a step failed, so that the server
    # does not keep raising alerts or hold an acknowledged one.
    undo = []
    undo << -> { unacknowledge_alert(cfg, acknowledged_alert) } if acknowledged_alert
    undo << -> { remove_override(cfg, override_rule) } if override_rule
    undo.each do |step|
      step.call
    rescue StandardError => e
      warn "Error: could not undo a change: #{e.message}"
      status = 1
    end
  end
  status
end

exit main
# --8<-- [end:main]
