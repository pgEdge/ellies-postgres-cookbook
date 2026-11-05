# Ellie's Postgres Cookbook
# Exchanging a client ID and secret for a pgEdge Starfleet access token,
# using Net::HTTP.
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

# Reads the API settings from the environment. The client ID and secret
# have no defaults, so a missing value becomes nil, and the token request
# reports it.
def settings
  {
    base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
    client_id: env_or("STARFLEET_CLIENT_ID", nil),
    client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
  }
end
# --8<-- [end:config]

# --8<-- [start:token]
# An error reply from the API.
class ApiError < StandardError; end

# Exchanges the client ID and secret for an access token. The token
# endpoint belongs to the account API, and accepts the OAuth 2.0 client
# credentials grant as a JSON body.
def get_token(config)
  unless config[:client_id] && config[:client_secret]
    raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
  end

  uri = URI("#{config[:base_url]}/account/v1/oauth/token")
  body = {
    grant_type: "client_credentials",
    client_id: config[:client_id],
    client_secret: config[:client_secret]
  }.to_json
  # Net::HTTP has no overall timeout, so limit both the connection and
  # each read.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.post(uri.request_uri, body, "Content-Type" => "application/json")
  end
  if response.code.to_i >= 400
    raise ApiError, "POST #{uri.path} failed with status #{response.code}: " \
                    "#{response.body.to_s.strip}"
  end

  token = JSON.parse(response.body)
  raise "the token response has no access token" if token["access_token"].to_s.empty?

  token
end
# --8<-- [end:token]

# --8<-- [start:main]
def main
  token = get_token(settings)
  # Never print the token itself; it grants access to the account.
  puts "Token type: #{token.fetch('token_type')}"
  puts "Token length: #{token['access_token'].length} characters"
  puts "Expires in: #{token.fetch('expires_in')} seconds"
  0
# Net::HTTP raises errors of several classes for a failed request: for
# example SystemCallError for a refused connection and Net::OpenTimeout,
# a Timeout::Error, for a timeout.
rescue ApiError, SystemCallError, IOError, SocketError, Timeout::Error => e
  warn "API error: #{e.message}"
  1
rescue StandardError => e
  warn "Error: #{e.message}"
  1
end

exit main
# --8<-- [end:main]
