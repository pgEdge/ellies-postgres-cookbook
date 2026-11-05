# Ellie's Postgres Cookbook
# Listing the regions, sizes, and PostgreSQL versions that the pgEdge
# Starfleet Managed API offers, using Net::HTTP.
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

# Sends a request with a JSON body, if there is one, and returns the
# decoded JSON reply. Net::HTTP has no overall timeout, so this limits
# both the connection and each read.
def request_json(method, url, headers, body = nil)
  uri = URI(url)
  headers = headers.merge("Content-Type" => "application/json") if body
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.send_request(method, uri.request_uri, body&.to_json, headers)
  end
  if response.code.to_i >= 400
    raise ApiError, "#{method} #{uri.path} failed with status #{response.code}: " \
                    "#{response.body.to_s.strip}"
  end
  JSON.parse(response.body)
end

# Exchanges the client ID and secret for an access token, which the
# Managed API accepts as a bearer token until it expires.
def get_token(config)
  unless config[:client_id] && config[:client_secret]
    raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
  end

  request_json("POST", "#{config[:base_url]}/account/v1/oauth/token", {}, {
                 grant_type: "client_credentials",
                 client_id: config[:client_id],
                 client_secret: config[:client_secret]
               }).fetch("access_token")
end
# --8<-- [end:token]

# --8<-- [start:api]
# Sends an authenticated GET request to the Managed API and returns the
# decoded JSON reply.
def api_get(config, token, path, params = {})
  url = "#{config[:base_url]}/managed/v1#{path}"
  url += "?#{URI.encode_www_form(params)}" unless params.empty?
  request_json("GET", url, { "Authorization" => "Bearer #{token}" })
end
# --8<-- [end:api]

# --8<-- [start:regions]
# Returns the identifiers of the regions that can host a database.
def list_regions(config, token)
  api_get(config, token, "/regions").map { |r| r.fetch("region") }
end
# --8<-- [end:regions]

# --8<-- [start:sizes]
# Returns a description of each size, smallest first.
def list_sizes(config, token)
  # The pricing option asks the API to include each size's price, which
  # takes a little longer because the API looks it up from billing.
  api_get(config, token, "/sizes", include: "pricing").map do |size|
    line = "#{size.fetch('name')}: #{size.fetch('connections')} connections, " \
           "#{size.fetch('storage_size')} storage"
    # A size with no configured price omits the pricing field. The amount
    # is in the smallest unit of the currency, such as cents.
    price = size["pricing"]
    if price
      line += format(", %.2f %s per %s", price.fetch("price_amount") / 100.0,
                     price.fetch("currency"), price.fetch("billing_interval"))
    end
    line
  end
end
# --8<-- [end:sizes]

# --8<-- [start:versions]
# Returns the PostgreSQL major versions, newest first, marking the one
# that a new database gets by default.
def list_versions(config, token)
  api_get(config, token, "/pg-versions").map do |v|
    v.fetch("version") + (v["default"] ? " (default)" : "")
  end
end
# --8<-- [end:versions]

# --8<-- [start:main]
def main
  config = settings
  token = get_token(config)

  puts "Regions:"
  list_regions(config, token).each { |region| puts "  #{region}" }

  puts "Sizes (smallest first):"
  list_sizes(config, token).each { |size| puts "  #{size}" }

  puts "PostgreSQL versions:"
  list_versions(config, token).each { |version| puts "  #{version}" }
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
