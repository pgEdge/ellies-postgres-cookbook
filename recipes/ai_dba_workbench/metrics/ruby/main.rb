# Ellie's Postgres Cookbook
# Querying metrics and top queries with the AI DBA Workbench API, using
# Net::HTTP.
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
# Sends a GET request to the API, with the parameters in the query string,
# and returns the decoded reply. A request that the server rejects raises
# an error that includes the message from the server.
def api(cfg, path, params)
  uri = URI("#{cfg[:base_url]}/api/v1#{path}")
  uri.query = URI.encode_www_form(params)

  # Net::HTTP has no overall timeout, so limit both the connection and
  # each read.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.get(uri.request_uri, "Authorization" => "Bearer #{cfg[:token]}")
  end
  if response.code.to_i >= 400
    raise "GET #{path} failed with status #{response.code}: " \
          "#{response.body.to_s.strip}"
  end
  JSON.parse(response.body)
end
# --8<-- [end:request]

# --8<-- [start:query_metrics]
# Prints one line for each series that the pg_stat_database probe collected
# over the last hour, in six buckets: the metric, the number of points, and
# the latest value.
def query_metrics(cfg)
  series = api(cfg, "/metrics/query", {
                 connection_id: cfg[:connection_id],
                 probe_name: "pg_stat_database",
                 time_range: "1h",
                 buckets: 6,
                 metrics: "numbackends,xact_commit"
               })
  raise "The Workbench returned no series; has the collector run yet?" if series.empty?

  series.each do |s|
    points = s["data"] || []
    if points.empty?
      puts "#{s.fetch('name')}: no data"
      next
    end
    puts "#{s.fetch('name')}: #{points.length} points, " \
         "latest #{points.last.fetch('value')}"
  end
end
# --8<-- [end:query_metrics]

# --8<-- [start:top_queries]
# Prints the queries that have used the most execution time, as the
# pg_stat_statements extension on the monitored server recorded them. The
# query text is cut to 50 characters on one line.
def top_queries(cfg)
  queries = api(cfg, "/metrics/top-queries", {
                  connection_id: cfg[:connection_id],
                  limit: 5,
                  order_by: "total_exec_time",
                  exclude_collector: "true"
                })
  if queries.empty?
    puts "No statements recorded (is pg_stat_statements installed?)"
    return
  end

  puts "Top queries by total execution time:"
  queries.each.with_index(1) do |q, rank|
    text = q.fetch("query").split.join(" ")[0, 50]
    puts "#{rank}. #{q.fetch('calls')} calls, " \
         "#{q.fetch('mean_exec_time').round(2)} ms mean: #{text}"
  end
end
# --8<-- [end:top_queries]

# --8<-- [start:main]
def main
  cfg = settings
  query_metrics(cfg)
  top_queries(cfg)
  0
# Net::HTTP raises errors of many classes, such as SystemCallError for a
# refused connection and Net::OpenTimeout for a timeout, and the program
# raises RuntimeError for replies that the server rejected or that lacked
# what we need, so this catches StandardError, their common ancestor.
rescue StandardError => e
  warn "Error: #{e.message}"
  1
end

exit main
# --8<-- [end:main]
