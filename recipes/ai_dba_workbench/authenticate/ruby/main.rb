# Ellie's Postgres Cookbook
# Authenticating with the AI DBA Workbench API, using Net::HTTP.
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
  username = env_or("WORKBENCH_USERNAME", nil)
  password = env_or("WORKBENCH_PASSWORD", nil)
  unless username && password
    raise "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
  end

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    username: username,
    password: password
  }
end
# --8<-- [end:config]

# --8<-- [start:request]
# Sends a request to the API and returns the response. The body, if given,
# is sent as JSON. A request that the server rejects raises an error that
# includes the message from the server.
def api(method, base_url, path, token = nil, body = nil)
  uri = URI("#{base_url}/api/v1#{path}")
  headers = {}
  headers["Authorization"] = "Bearer #{token}" if token
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
  response
end
# --8<-- [end:request]

# --8<-- [start:login]
# Logs in and returns the session token. The server returns the token in a
# session_token cookie, not in the body of the reply.
def login(base_url, username, password)
  response = api("POST", base_url, "/auth/login", nil,
                 { username: username, password: password })
  (response.get_fields("set-cookie") || []).each do |cookie|
    match = /\Asession_token=([^;]*)/.match(cookie)
    return match[1] if match
  end
  raise "The login reply had no session_token cookie"
end
# --8<-- [end:login]

# --8<-- [start:user_info]
# Returns the user that a token belongs to, with its superuser flag.
def user_info(base_url, token)
  info = JSON.parse(api("GET", base_url, "/user/info", token).body)
  "#{info.fetch('username')} (superuser: #{info.fetch('is_superuser')})"
end
# --8<-- [end:user_info]

# --8<-- [start:create_token]
# Creates an API token for a user and returns its ID and its value. The
# server shows the value only once. The token expires after an hour.
def create_token(base_url, session, owner, annotation)
  response = api("POST", base_url, "/rbac/tokens", session, {
                   owner_username: owner,
                   annotation: annotation,
                   expires_in: "1h"
                 })
  created = JSON.parse(response.body)
  [created.fetch("id"), created.fetch("token")]
end
# --8<-- [end:create_token]

# --8<-- [start:delete_token]
# Deletes an API token by its ID.
def delete_token(base_url, session, token_id)
  api("DELETE", base_url, "/rbac/tokens/#{token_id}", session)
end
# --8<-- [end:delete_token]

# --8<-- [start:main]
def main
  token_id = nil
  status = 0
  begin
    config = settings
    base_url = config[:base_url]

    session = login(base_url, config[:username], config[:password])
    puts "Logged in with a session token"
    puts "Session token belongs to #{user_info(base_url, session)}"

    token_id, api_token = create_token(base_url, session, config[:username],
                                       "cookbook-authenticate")
    puts "Created the API token 'cookbook-authenticate'"
    puts "API token belongs to #{user_info(base_url, api_token)}"
  # Net::HTTP raises errors of many classes, such as SystemCallError for a
  # refused connection and Net::OpenTimeout for a timeout, and the program
  # raises RuntimeError for replies that the server rejected or that lacked
  # what we need, so this catches StandardError, their common ancestor.
  rescue StandardError => e
    warn "Error: #{e.message}"
    status = 1
  ensure
    # Delete the token whether or not a later step failed, so that a
    # failed run does not leave a token behind.
    if token_id
      begin
        delete_token(base_url, session, token_id)
        puts "Deleted the API token"
      rescue StandardError => e
        warn "Error: could not delete the token: #{e.message}"
        status = 1
      end
    end
  end
  status
end

exit main
# --8<-- [end:main]
